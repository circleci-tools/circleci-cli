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
          stop_polling
          update_build
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
          thread = @poll_lock.synchronize do
            thread = @build_thread
            @build_thread = nil
            thread&.kill
            thread
          end
          thread&.join
        end

        def poll_build
          @build_thread = Thread.new do
            count = 0
            loop do
              poll_once(refresh_build: (count % 5).zero?)
              count += 1
              sleep 1
            end
          end
        end

        def poll_once(refresh_build:)
          @poll_lock.synchronize do
            update_build if refresh_build
            update_actions
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
          log = @messages.delete(step_key(step))
          log&.write_to($stdout) if status == 'failed'
        ensure
          log&.close
        end

        def step_key(step)
          action = step.actions.first
          [action&.index, action&.step, step.name]
        end

        # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        def update_build
          build = CircleCI::CLI::Response::Build.get(@build.username, @build.reponame, @build.build_number)
          previous_statuses = @steps.group_by(&:name).transform_values { |steps| steps.map(&:status).uniq }
          steps = build.steps.each do |step|
            statuses = previous_statuses[step.name]
            next on_new_step(step) unless statuses

            on_new_step_status(step) unless statuses == [step.status]
          end
          @steps = steps

          next_step = steps.find { |step| step.status == 'running' }
          @read_byte = 0 if (@current_step && step_key(@current_step)) != (next_step && step_key(next_step))
          @current_step = next_step
        end

        def update_actions
          return unless @current_step

          url = "https://circleci.com/api/private/output/raw/github/#{@build.username}/#{@build.reponame}/#{@build.build_number}/output/#{@current_step.actions.first.index}/#{@current_step.actions.first.step}"
          headers = { 'Range' => "bytes=#{@read_byte}-" }
          Networking::HTTPClient.get_raw(url, headers) { |response| read_output(response) }
        end

        def read_output(response)
          needs_newline = false
          response.read_body do |chunk|
            next if chunk.empty?

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
            (@messages[step_key(@current_step)] ||= StepLog.new).append(chunk)
          end
        end

        def notify_started
          say Printer::BuildPrinter.header_for(
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

          @verbose ? print_bordered(text) : say(text)
        end

        def print_bordered(text)
          say Terminal::Table.new(rows: [[text]], style: { width: 120 }).to_s
        end
      end
    end
  end
end
