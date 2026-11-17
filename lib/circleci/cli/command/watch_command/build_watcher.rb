# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class BuildWatcher
        attr_reader :build

        def initialize(build, verbose: false)
          @build = build
          @verbose = verbose
          @messages = Hash.new { |h, k| h[k] = [] }

          @stop_requested = Queue.new

          @steps = build.steps
          @current_step = nil
          @read_byte = 0
        end

        def start
          notify_started
          @build_thread = poll_build
        end

        def stop(status)
          @stop_requested.close
          @build_thread ||= poll_build
          @build_thread.join
          notify_stopped(status)
        end

        private

        def poll_build
          Thread.new do
            count = 0
            until @stop_requested.closed?
              update_build if (count % 5).zero?
              update_actions

              count += 1
              @stop_requested.pop(timeout: 1)
            end
            update_build
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
            @messages[step.name].each(&method(:say))
          end
        end

        # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        def update_build
          steps = CircleCI::CLI::Response::Build.get(@build.username, @build.reponame, @build.build_number).steps
          steps.each do |step|
            on_new_step(step) unless @steps.any? { |s| s.name == step.name }
            on_new_step_status(step) if @steps.any? { |s| s.name == step.name && s.status != step.status }
          end

          @steps = steps

          next_step = steps.find { |s| s.status == 'running' }
          @read_byte = 0 if @current_step&.name != next_step&.name
          @current_step = next_step
        end

        # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
        def update_actions
          return unless @current_step

          url = "https://circleci.com/api/private/output/raw/github/#{@build.username}/#{@build.reponame}/#{@build.build_number}/output/#{@current_step.actions.first.index}/#{@current_step.actions.first.step}"
          headers = { 'Range' => "bytes=#{@read_byte}-" }
          res = HTTPClient.get(url, headers)

          response = res.body

          return if response.empty?

          @read_byte += response.bytesize

          if @verbose
            Thor::Shell::Basic.new.say(response, nil, false)
          else
            @messages[@current_step.name] << response
          end
        end

        def notify_started
          say Printer::BuildPrinter.header_for(
            @build,
            "👀 Start watching #{@build.project_name} ##{@build.build_number}"
          )
        end

        def notify_stopped(status)
          text = case status
                 when 'success'
                   Printer.colorize_green("🎉 #{@build.project_name} ##{@build.build_number} has succeeded!")
                 when 'failed'
                   Printer.colorize_red("😥 #{@build.project_name} ##{@build.build_number} has failed...")
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
