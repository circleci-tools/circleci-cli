# frozen_string_literal: true

require 'circleci/cli/command/watch_command/step_log'

module CircleCI
  module CLI
    module Command
      class BuildWatcher # rubocop:disable Metrics/ClassLength
        attr_reader :build

        def initialize(build, verbose: false)
          @build = build
          @verbose = verbose
          @messages = {}

          @build_thread = nil
          @poll_lock = Mutex.new

          @steps = build.steps
          @current_step = nil
          @read_byte = 0
        end

        def start
          poll_build
          notify_started
        end

        def stop(status)
          @poll_lock.synchronize { stop_polling }
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
        end

        private

        def stop_polling
          Thread.handle_interrupt(Interrupt => :never) do
            @build_thread&.kill
            @build_thread&.join
            @build_thread = nil
          end
        end

        def poll_build
          @build_thread = Thread.new do
            0.step do |count|
              @poll_lock.synchronize do
                update_build if (count % 5).zero?
                update_actions
              end

              sleep 1
            end
          end
        end

        # rubocop:disable-next Metrics/MethodLength
        def on_new_step(step)
          if @verbose
            print_bordered step.name
          else
            case step.status
            when 'success'
              puts "\e[2K\r#{Printer.colorize_green(step.name)}"
            when 'failed'
              puts "\e[2K\r#{Printer.colorize_red(step.name)}"
            else
              puts step.name
            end
          end
        end

        def on_new_step_status(step)
          return if @verbose

          status = step.status
          case status
          when 'success'
            puts "\e[1A\e[2K\r#{Printer.colorize_green(step.name)}"
          when 'failed'
            puts "\e[1A\e[2K\r#{Printer.colorize_red(step.name)}"
          end
          finish_step_log(step, status) unless status == 'running'
        end

        def finish_step_log(step, status)
          key = step_key(step)
          log = @messages[key]
          log&.write_to($stdout) if status == 'failed'
        ensure
          log&.close
          @messages.delete(key)
        end

        def step_key(step)
          action = step.actions.first
          [action&.index, action&.step, step.name]
        end

        def update_build(stopping: false)
          build = CircleCI::CLI::Response::Build.get(@build.username, @build.reponame, @build.build_number)
          steps = build.steps
          next_step = steps.find { |step| step.status == 'running' } unless stopping
          action_changed = action_position(@current_step) != action_position(next_step)
          update_actions if action_changed

          notify_step_changes(steps)
          @steps = steps
          @read_byte = 0 if action_changed
          @current_step = next_step
        end

        def notify_step_changes(steps)
          previous_statuses = @steps.to_h { |step| [step_key(step), step.status] }
          steps.each do |step|
            previous_status = previous_statuses[step_key(step)]
            next on_new_step(step) unless previous_status

            on_new_step_status(step) unless previous_status == step.status
          end
        end

        def action_position(step)
          action = step&.actions&.first
          [action.index, action.step] if action
        end

        def update_actions
          position = action_position(@current_step)
          return unless position

          url = "https://circleci.com/api/private/output/raw/github/#{@build.username}/#{@build.reponame}/#{@build.build_number}/output/#{position.join('/')}"
          headers = { 'Range' => "bytes=#{@read_byte}-" }
          Networking::HTTPClient.get_raw(url, headers) { |response| read_output(response) }
        rescue EOFError, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout,
               Errno::ECONNRESET, Errno::ECONNABORTED, Errno::EPIPE, Errno::ETIMEDOUT, Errno::ECONNREFUSED
          # The next poll requests the remaining bytes.
        end

        def read_output(response)
          successful = response.is_a?(Net::HTTPSuccess)
          needs_newline = false
          response.read_body do |chunk|
            next if !successful || chunk.empty?

            write_output(chunk)
            @read_byte += chunk.bytesize
            needs_newline = !chunk.end_with?("\n")
          end
          write_output("\n") if needs_newline && !@verbose
        end

        def write_output(chunk)
          if @verbose
            $stdout.write(chunk)
            $stdout.flush
          else
            # Defer thread termination until any spill file is registered for cleanup.
            Thread.handle_interrupt(Object => :never) do
              (@messages[step_key(@current_step)] ||= StepLog.new).append(chunk)
            end
          end
        end

        def notify_started
          puts Printer::BuildPrinter.header_for(
            @build,
            "👀 Start watching #{@build.project_name} ##{@build.build_number}"
          )
        end

        def notify_stopped(status)
          build_name = "#{@build.project_name} ##{@build.build_number}"
          text = case status
                 when 'success' then Printer.colorize_green("🎉 #{build_name} has succeeded!")
                 when 'failed' then Printer.colorize_red("😥 #{build_name} has failed...")
                 when 'canceled' then Printer.colorize_yellow("#{build_name} was canceled.")
                 when 'no_tests' then Printer.colorize_light_black("#{build_name} ran no tests.")
                 end

          @verbose ? print_bordered(text) : puts(text)
        end

        def print_bordered(text)
          puts Terminal::Table.new(rows: [[text]], style: { width: 120 })
        end
      end
    end
  end
end
