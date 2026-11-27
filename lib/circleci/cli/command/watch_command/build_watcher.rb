# frozen_string_literal: true

require 'circleci/cli/command/watch_command/action_log_tracker'
require 'circleci/cli/command/watch_command/action_output'
require 'circleci/cli/command/watch_command/build_announcer'
require 'circleci/cli/command/watch_command/request_errors'
require 'circleci/cli/command/watch_command/step_log'
require 'circleci/cli/command/watch_command/step_notifier'

module CircleCI
  module CLI
    module Command
      class BuildWatcher # rubocop:disable Metrics/ClassLength
        FINAL_DETAIL_ATTEMPTS = 2
        MAX_CONCURRENT_LOG_READS = 4

        attr_reader :build

        def initialize(build, verbose: false)
          @build = build
          @verbose = verbose
          @steps = build.steps
          @current_step = nil

          initialize_polling
          initialize_collaborators
        end

        def start
          notify_started
          @build_thread = poll_build
        end

        def latest_detail
          @state_lock.synchronize { @latest_detail }
        end

        def poll_error
          @state_lock.synchronize { @poll_error }
        end

        def disable_step_line_rewrites
          @step_notifier.disable_step_line_rewrites
        end

        def stop(status)
          @stop_requested.close
          (@build_thread ||= poll_build).join
          error = poll_error
          raise error if error

          @announcer.notify_stopped(status)
        ensure
          close
        end

        def close
          stop_polling
        ensure
          @action_log_tracker.close
          @log_sessions.each(&:close)
        end

        private

        def initialize_polling
          @stop_requested = Queue.new
          @state_lock = Mutex.new
          @log_sessions = Array.new(MAX_CONCURRENT_LOG_READS) { Networking::HTTPClient::Session.new }
          @messages = {}
        end

        def initialize_collaborators
          @step_notifier = build_step_notifier
          @action_log_tracker = build_action_log_tracker
          @announcer = build_announcer
        end

        def build_step_notifier
          StepNotifier.new(
            verbose: @verbose,
            puts: ->(text) { puts(text) },
            bordered: ->(text) { print_bordered(text) }
          )
        end

        def build_action_log_tracker
          ActionLogTracker.new(
            @build,
            verbose: @verbose,
            log_sessions: @log_sessions,
            messages: @messages,
            output: ->(chunk) { print_output(chunk) }
          )
        end

        def build_announcer
          BuildAnnouncer.new(
            @build,
            verbose: @verbose,
            puts: ->(text) { puts(text) },
            bordered: ->(text) { print_bordered(text) }
          )
        end

        def stop_polling
          Thread.handle_interrupt(Interrupt => :never) do
            @build_thread.kill.join if @build_thread&.alive?
          ensure
            @build_thread = nil
          end
        end

        def poll_build
          Thread.new do
            poll_live
            update_build(stopping: true)
          rescue StandardError => e
            @state_lock.synchronize { @poll_error = e }
          ensure
            @log_sessions.each(&:close)
          end
        end

        def poll_live
          next_build_poll = 0
          0.step do |count|
            break if @stop_requested.closed?

            poll_safely do
              next_build_poll = refresh_live_build(count) if count >= next_build_poll
              update_actions
            end
            @stop_requested.pop(timeout: 1)
          end
        end

        def refresh_live_build(count)
          update_build
          count + 5
        end

        def poll_safely
          yield
        rescue *WatchRequestErrors::TRANSIENT
          # Resume on the next poll with the last consumed byte offset.
        end

        def on_new_step(step)
          @step_notifier.on_new_step(step)
        end

        def on_new_step_status(step)
          @step_notifier.on_new_step_status(step)
        end

        def update_build(stopping: false)
          detail = fetch_detail(attempts: stopping ? FINAL_DETAIL_ATTEMPTS : 1)
          update_steps(detail.steps, stopping:)
          @state_lock.synchronize { @latest_detail = detail }
        end

        def fetch_detail(attempts:)
          Response::Build.get(@build.username, @build.reponame, @build.build_number)
        rescue *WatchRequestErrors::TRANSIENT
          attempts -= 1
          retry if attempts.positive?
          raise
        end

        def update_steps(steps, stopping:)
          next_step = steps.find { |step| step.status == 'running' } unless stopping
          continuing = refresh_current_step(steps, next_step, stopping:) if @current_step

          notify_step_changes(steps, next_step:, stopping:)
          @steps = steps
          @current_step = next_step
          return unless next_step && !continuing

          @action_log_tracker.refresh_action_outputs(next_step.actions, continuing: true)
        end

        def refresh_current_step(steps, next_step, stopping:)
          key = @current_step.identity
          continuing = next_step && next_step.identity == key
          updated_step = continuing ? next_step : steps.find { |step| step.identity == key }
          @action_log_tracker.refresh_action_outputs(updated_step&.actions || [], continuing:, stopping:)
          @action_log_tracker.clear_actions unless continuing
          continuing
        end

        def notify_step_changes(steps, next_step:, stopping:)
          previous_statuses = @steps.to_h { |step| [step.identity, step.status] }
          steps.each do |step|
            @step_notifier.notify_step_change(step, previous_statuses[step.identity])
            @action_log_tracker.finish_action_logs(step)
            next if step == next_step || (!@verbose && step.status == 'running')

            @action_log_tracker.print_completed_outputs(step, stopping:)
          end
        end

        def update_actions
          return unless @current_step

          @action_log_tracker.update_actions
        end

        def retain_output(identity, chunk)
          @action_log_tracker.retain_output(identity, chunk)
        end

        def print_output(chunk)
          $stdout.write(chunk)
          $stdout.flush
        end

        def notify_started
          puts Printer::BuildPrinter.header_for(
            @build,
            "👀 Start watching #{@build.project_name} ##{@build.build_number}"
          )
        end

        def print_bordered(text)
          puts Terminal::Table.new(rows: [[text]], style: { width: 120 })
        end
      end
    end
  end
end
