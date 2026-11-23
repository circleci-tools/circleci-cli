# frozen_string_literal: true

require 'circleci/cli/command/watch_command/action_output'
require 'circleci/cli/command/watch_command/request_errors'
require 'circleci/cli/command/watch_command/step_log'

module CircleCI
  module CLI
    module Command
      class BuildWatcher # rubocop:disable Metrics/ClassLength
        COMPLETION_MESSAGES = {
          'success' => '🎉 %<build>s has succeeded!',
          'fixed' => '🎉 %<build>s has been fixed!',
          'failed' => '😥 %<build>s has failed...',
          'timedout' => '%<build>s timed out.',
          'infrastructure_fail' => '%<build>s failed due to an infrastructure error.',
          'canceled' => '%<build>s was canceled.',
          'no_tests' => '%<build>s ran no tests.'
        }.freeze

        INCOMPLETE_OUTPUT_WARNING = 'Warning: Step log output may be incomplete.'
        FINAL_DETAIL_ATTEMPTS = 2
        MAX_CONCURRENT_LOG_READS = 4

        attr_reader :build

        def initialize(build, verbose: false)
          @build = build
          @verbose = verbose
          @messages = {}
          @retained_log_bytes = 0

          initialize_polling
          @steps = build.steps
          @current_step = nil
          @action_outputs = {}
          @completed_outputs = {}
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
          @state_lock.synchronize { @step_line_rewrites_disabled = true }
        end

        def stop(status)
          @stop_requested.close
          (@build_thread ||= poll_build).join
          error = poll_error
          raise error if error

          notify_stopped(status)
        ensure
          close
        end

        def close
          stop_polling
        ensure
          @messages.each_value(&:close)
          @messages.clear
          @retained_log_bytes = 0
          @log_sessions.each(&:close)
        end

        private

        def initialize_polling
          @stop_requested = Queue.new
          @state_lock = Mutex.new
          @output_lock = Mutex.new
          @log_sessions = Array.new(MAX_CONCURRENT_LOG_READS) { Networking::HTTPClient::Session.new }
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
          name = Printer.escape_controls(step.name)
          return print_bordered(name) if @verbose

          case step.status
          when 'success' then print_step_status(Printer.colorize_green(name))
          when 'failed' then print_step_status(Printer.colorize_red(name))
          else puts name
          end
        end

        def on_new_step_status(step)
          return if @verbose

          name = Printer.escape_controls(step.name)
          status = step.status
          case status
          when 'success'
            print_step_status(Printer.colorize_green(name), move_up: true)
          when 'failed'
            print_step_status(Printer.colorize_red(name), move_up: true)
          end
        end

        def print_step_status(text, move_up: false)
          @state_lock.synchronize do
            prefix = move_up ? "\e[1A\e[2K\r" : "\e[2K\r"
            puts(@step_line_rewrites_disabled ? text : "#{prefix}#{text}")
          end
        end

        def finish_action_logs(step)
          return if @messages.empty?

          running = step.status == 'running'
          step.actions.each do |action|
            next if action.end_time.nil? || (running && action.failed?)

            finish_action_log(action)
          end
        end

        def finish_action_log(action)
          log = @messages.delete(action.identity)
          return unless log

          log.write_to($stdout) if action.failed?
        ensure
          if log
            log.close
            @retained_log_bytes -= log.bytesize
          end
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
          continuing = refresh_current_step(steps, next_step) if @current_step

          notify_step_changes(steps, next_step:, stopping:)
          @steps = steps
          @current_step = next_step
          return unless next_step && !continuing

          refresh_action_outputs(next_step.actions, continuing: true)
        end

        def refresh_current_step(steps, next_step)
          key = @current_step.identity
          continuing = next_step && next_step.identity == key
          updated_step = continuing ? next_step : steps.find { |step| step.identity == key }
          refresh_action_outputs(updated_step&.actions || [], continuing:)
          @action_outputs.clear unless continuing
          continuing
        end

        def refresh_action_outputs(actions, continuing:)
          track_actions(actions.reject(&:skipped?))
          running = continuing ? actions.select(&:running?).map(&:identity) : []
          finish_outputs(running)
        end

        def track_actions(actions)
          actions.each do |action|
            next if action.identity.include?(nil) || (action.end_time && !show_action_log?(action))

            @action_outputs.fetch(action.identity) do |identity|
              @action_outputs[identity] = @completed_outputs.fetch(identity) { new_output(identity) }
            end
          end
        end

        def new_output(identity)
          project = [@build.username, @build.reponame, @build.build_number].join('/')
          url = "https://circleci.com/api/private/output/raw/github/#{project}/output/#{identity.join('/')}"
          ActionOutput.new(url, @log_sessions.first)
        end

        def notify_step_changes(steps, next_step:, stopping:)
          previous_statuses = @steps.to_h { |step| [step.identity, step.status] }
          steps.each do |step|
            notify_step_change(step, previous_statuses[step.identity])
            finish_action_logs(step)
            next if step == next_step || (!@verbose && step.status == 'running')

            print_completed_outputs(step, stopping:)
          end
        end

        def notify_step_change(step, previous_status)
          return on_new_step(step) unless previous_status

          on_new_step_status(step) unless previous_status == step.status
        end

        def show_action_log?(action)
          @verbose || action.failed?
        end

        def completed_log_actions(step)
          step.actions.select { |action| action.end_time && show_action_log?(action) }
        end

        def print_completed_outputs(step, stopping:)
          completed_log_actions(step).each do |action|
            identity = action.identity
            next if identity.include?(nil) || @action_outputs.key?(identity)

            output = @completed_outputs.fetch(identity) { @completed_outputs[identity] = new_output(identity) }
            next unless output

            read_completed_output(output, identity, stopping:)
          end
        end

        def read_completed_output(output, identity, stopping:)
          complete = output.finish_output?(final: stopping) { |chunk| print_output(chunk) }
          @completed_outputs[identity] = nil if complete || stopping
          warn INCOMPLETE_OUTPUT_WARNING if stopping && !complete
        end

        def finish_outputs(running)
          failed = @action_outputs.except(*running).filter_map do |identity, output|
            next unless output

            complete = output.finish_output? { |chunk| write_output(identity, chunk) }
            @action_outputs[identity] = nil
            @completed_outputs[identity] = nil
            identity unless complete
          end
          warn INCOMPLETE_OUTPUT_WARNING if failed.any?
        end

        def update_actions
          return unless @current_step

          actions = @action_outputs.compact
          return if actions.empty?
          return read_action(*actions.first, @log_sessions.first) if actions.one?

          read_actions_concurrently(actions)
        end

        def read_actions_concurrently(actions)
          workers = []
          pending = Queue.new
          actions.each { |entry| pending << entry }
          pending.close
          start_log_workers(workers, pending, actions.size)
          workers.each(&:value)
        ensure
          stop_log_workers(workers)
        end

        def start_log_workers(workers, pending, count)
          Thread.handle_interrupt(Object => :never) do
            @log_sessions.take(count).each do |session|
              workers << Thread.new { read_pending_actions(pending, session) }
            end
          end
        end

        def stop_log_workers(workers)
          workers.each(&:kill)
          workers.each { |worker| worker.join if worker.alive? }
        end

        def read_pending_actions(pending, session)
          while (entry = pending.pop)
            read_action(*entry, session)
          end
        end

        def read_action(identity, output, session)
          output.read(session:) { |chunk| write_output(identity, chunk) }
        end

        def write_output(identity, chunk)
          @output_lock.synchronize do
            if @verbose
              print_output(chunk)
            else
              # Defer thread termination until any spill file is registered for cleanup.
              Thread.handle_interrupt(Object => :never) do
                retain_output(identity, chunk)
              end
            end
          end
        end

        def print_output(chunk)
          $stdout.write(chunk)
          $stdout.flush
        end

        def retain_output(identity, chunk)
          log = (@messages[identity] ||= StepLog.new)
          remaining = StepLog::RETENTION_LIMIT - @retained_log_bytes
          @retained_log_bytes += log.append(chunk, remaining:)
        end

        def notify_started
          puts Printer::BuildPrinter.header_for(
            @build,
            "👀 Start watching #{@build.project_name} ##{@build.build_number}"
          )
        end

        def notify_stopped(status)
          build_name = Printer.escape_controls("#{@build.project_name} ##{@build.build_number}")
          text = completion_message(status, build_name)
          @verbose ? print_bordered(text) : puts(text)
        end

        def completion_message(status, build_name)
          template = COMPLETION_MESSAGES.fetch(status) do
            return "#{build_name} finished (status: #{Printer.escape_controls(status || 'unknown')})."
          end
          Printer.colorize_by_status(format(template, build: build_name), status)
        end

        def print_bordered(text)
          puts Terminal::Table.new(rows: [[text]], style: { width: 120 })
        end
      end
    end
  end
end
