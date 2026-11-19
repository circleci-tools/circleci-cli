# frozen_string_literal: true

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
          @messages = Hash.new { |h, k| h[k] = [] }

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
          @poll_lock.synchronize do
            @build_thread&.kill
            update_build(stopping: true)
          end
          notify_stopped(status)
        end

        private

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
          case step.status
          when 'success'
            puts "\e[1A\e[2K\r#{Printer.colorize_green(name)}"
          when 'failed'
            puts "\e[1A\e[2K\r#{Printer.colorize_red(name)}"
            @messages[step.name].each(&method(:puts))
          end
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
          previous_statuses = @steps.group_by(&:name).transform_values { |steps| steps.map(&:status).uniq }
          steps.each do |step|
            statuses = previous_statuses[step.name]
            next on_new_step(step) unless statuses

            on_new_step_status(step) unless statuses == [step.status]
          end
        end

        def action_position(step)
          action = step&.actions&.first
          [action.index, action.step] if action
        end

        def update_actions
          return unless @current_step

          response = read_action_output
          return if response.nil? || response.empty?

          @read_byte += response.bytesize

          response = Printer.escape_controls(response, multiline: true)
          if @verbose
            Thor::Shell::Basic.new.say(response, nil, false)
          else
            @messages[@current_step.name] << response
          end
        end

        def read_action_output
          position = action_position(@current_step).join('/')
          url = "https://circleci.com/api/private/output/raw/github/#{@build.username}/#{@build.reponame}/#{@build.build_number}/output/#{position}"
          response = Networking::HTTPClient.get_raw(url, 'Range' => "bytes=#{@read_byte}-")
          response.body if response.is_a?(Net::HTTPSuccess)
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
