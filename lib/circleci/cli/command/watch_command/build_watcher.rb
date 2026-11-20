# frozen_string_literal: true

require 'circleci/cli/command/watch_command/action_output'
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
        end

        def start
          poll_build
          notify_started
        end

        def latest_detail
          @state_lock.synchronize { @latest_detail }
        end

        def poll_error
          @state_lock.synchronize { @poll_error }
        end

        def stop(status)
          @poll_lock.synchronize do
            error = poll_error
            raise error if error

            stop_polling
          end
          update_build(stopping: true)
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
          @log_session.close
        end

        private

        def initialize_polling
          @poll_lock = Mutex.new
          @state_lock = Mutex.new
          @log_session = Networking::HTTPClient::Session.new
        end

        def stop_polling
          Thread.handle_interrupt(Interrupt => :never) do
            @build_thread&.kill
            @build_thread&.join
            @build_thread = nil
          end
        end

        def poll_build
          @build_thread = Thread.new do
            poll_live
          ensure
            @log_session.close
          end
        end

        def poll_live
          next_build_poll = 0
          0.step do |count|
            poll_safely do
              next_build_poll = refresh_live_build(count) if count >= next_build_poll
              update_actions
            end
            break if poll_error

            sleep 1
          end
        end

        def refresh_live_build(count)
          update_build
          count + 5
        end

        def poll_safely
          @poll_lock.synchronize do
            yield
          rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout,
                 Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EPIPE, EOFError
            # Resume on the next poll with the last consumed byte offset.
          rescue StandardError => e
            @state_lock.synchronize { @poll_error = e }
          end
        end

        def on_new_step(step)
          name = Printer.escape_controls(step.name)
          return print_bordered(name) if @verbose

          case step.status
          when 'success' then puts "\e[2K\r#{Printer.colorize_green(name)}"
          when 'failed' then puts "\e[2K\r#{Printer.colorize_red(name)}"
          else puts name
          end
        end

        def on_new_step_status(step)
          return if @verbose

          name = Printer.escape_controls(step.name)
          status = step.status
          case status
          when 'success'
            puts "\e[1A\e[2K\r#{Printer.colorize_green(name)}"
          when 'failed'
            puts "\e[1A\e[2K\r#{Printer.colorize_red(name)}"
          end
          finish_step_log(step, status) unless status == 'running'
        end

        def finish_step_log(step, status)
          key = step_key(step)
          log = @messages[key]
          log&.write_to($stdout) if status == 'failed'
        ensure
          if log
            log.close
            @retained_log_bytes -= log.bytesize
          end
          @messages.delete(key)
        end

        def step_key(step)
          step.action_identity || step.name
        end

        def update_build(stopping: false)
          detail = Response::Build.get(@build.username, @build.reponame, @build.build_number)
          update_steps(detail.steps, stopping:)
          @state_lock.synchronize { @latest_detail = detail }
        end

        def update_steps(steps, stopping:)
          next_step = steps.find { |step| step.status == 'running' } unless stopping
          continuing = refresh_current_step(steps, next_step) if @current_step

          notify_step_changes(steps)
          @steps = steps
          @current_step = next_step
          return unless next_step && !continuing

          refresh_action_outputs(next_step.actions, key: step_key(next_step), continuing: true)
        end

        def refresh_current_step(steps, next_step)
          key = step_key(@current_step)
          continuing = next_step && step_key(next_step) == key
          updated_step = continuing ? next_step : steps.find { |step| step_key(step) == key }
          refresh_action_outputs(updated_step&.actions || [], key:, continuing:)
          @action_outputs.clear unless continuing
          continuing
        end

        def refresh_action_outputs(actions, key:, continuing:)
          track_actions(actions)
          running = continuing ? actions.select { |action| action.end_time.nil? }.map(&:identity) : []
          finish_outputs(running, key)
        end

        def track_actions(actions)
          actions.each do |action|
            @action_outputs.fetch(action.identity) do |identity|
              @action_outputs[identity] = ActionOutput.new(output_url(identity), @log_session)
            end
          end
        end

        def output_url(identity)
          project = [@build.username, @build.reponame, @build.build_number].join('/')
          "https://circleci.com/api/private/output/raw/github/#{project}/output/#{identity.join('/')}"
        end

        def notify_step_changes(steps)
          previous_statuses = @steps.to_h { |step| [step_key(step), step.status] }
          steps.each do |step|
            previous_status = previous_statuses[step_key(step)]
            next on_new_step(step) unless previous_status

            on_new_step_status(step) unless previous_status == step.status
          end
        end

        def finish_outputs(running, key)
          failed = @action_outputs.except(*running).filter_map do |identity, output|
            next unless output

            complete = output.finish_output? { |chunk| write_output(key, chunk) }
            @action_outputs[identity] = nil
            identity unless complete
          end
          warn 'Warning: Step log output may be incomplete.' if failed.any?
        end

        def update_actions
          return unless @current_step

          key = step_key(@current_step)
          @action_outputs.each_value { |output| output&.read { |chunk| write_output(key, chunk) } }
        end

        def write_output(key, chunk)
          if @verbose
            $stdout.write(chunk)
            $stdout.flush
          else
            # Defer thread termination until any spill file is registered for cleanup.
            Thread.handle_interrupt(Object => :never) do
              retain_output(key, chunk)
            end
          end
        end

        def retain_output(key, chunk)
          log = (@messages[key] ||= StepLog.new)
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
