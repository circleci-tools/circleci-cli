# frozen_string_literal: true

require 'circleci/cli/command/watch_command/step_log'

module CircleCI
  module CLI
    module Command
      class BuildWatcher # rubocop:disable Metrics/ClassLength
        OUTPUT_READ_ERRORS = [
          EOFError, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Errno::ECONNRESET,
          Errno::ECONNABORTED, Errno::EPIPE, Errno::ETIMEDOUT, Errno::ECONNREFUSED
        ].freeze
        OUTPUT_SUFFIX = /(?:\r|[\xC2-\xDF]|[\xE0-\xEF][\x80-\xBF]?|[\xF0-\xF4][\x80-\xBF]{0,2})\z/n

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
          @output_suffix = ''.b
          @needs_newline = false
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
          log&.close
          @messages.delete(key)
        end

        def step_key(step)
          action = step.actions.first
          [action&.index, action&.step, step.name]
        end

        def update_build(stopping: false)
          steps = fetch_steps
          next_step = steps.find { |step| step.status == 'running' } unless stopping
          action_changed = action_position(@current_step) != action_position(next_step)
          incomplete_output = action_changed && !finish_action_output?

          notify_step_changes(steps)
          warn 'Warning: Step log output may be incomplete.' if incomplete_output
          @steps = steps
          @read_byte = 0 if action_changed
          @current_step = next_step
        end

        def fetch_steps
          CircleCI::CLI::Response::Build.get(@build.username, @build.reponame, @build.build_number).steps
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

        def finish_action_output?
          return true if 2.times.any? { update_actions }

          flush_output
          false
        end

        def update_actions
          position = action_position(@current_step)
          return true unless position

          url = "https://circleci.com/api/private/output/raw/github/#{@build.username}/#{@build.reponame}/#{@build.build_number}/output/#{position.join('/')}"
          headers = { 'Range' => "bytes=#{@read_byte}-" }
          complete = false
          Networking::HTTPClient.get_raw(url, headers) { |response| complete = read_output(response) }
          flush_output if complete
          complete
        rescue *OUTPUT_READ_ERRORS
          false
        end

        def output_response?(response)
          response.is_a?(Net::HTTPPartialContent) || (@read_byte.zero? && response.is_a?(Net::HTTPSuccess))
        end

        def read_output(response)
          successful = output_response?(response)
          response.ignore_eof = false
          response.read_body do |chunk|
            next if !successful || chunk.empty?

            stream_output(chunk.b)
            @read_byte += chunk.bytesize
            @needs_newline = !chunk.end_with?("\n")
          end
          successful || response.is_a?(Net::HTTPRangeNotSatisfiable)
        end

        def stream_output(chunk)
          # Retain a partial UTF-8 character or CRLF across chunks and interrupted reads.
          text = @output_suffix + chunk
          @output_suffix = text.slice!(OUTPUT_SUFFIX) || ''.b
          write_escaped_output(text)
        end

        def flush_output
          write_escaped_output(@output_suffix)
          write_output("\n") if @needs_newline && !@verbose
          @output_suffix = ''.b
          @needs_newline = false
        end

        def write_escaped_output(text)
          write_output(Printer.escape_controls(text, multiline: true)) unless text.empty?
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
          build_name = Printer.escape_controls("#{@build.project_name} ##{@build.build_number}")
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
