# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class BuildWatcher # rubocop:disable Metrics/ClassLength
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

          case step.status
          when 'success'
            puts "\e[1A\e[2K\r#{Printer.colorize_green(step.name)}"
          when 'failed'
            puts "\e[1A\e[2K\r#{Printer.colorize_red(step.name)}"
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
