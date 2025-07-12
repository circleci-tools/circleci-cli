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

          @build_thread = nil
          @step_thread = nil

          @steps = build.steps
        end

        def start
          poll_build
          notify_started
        end

        def stop(status)
          update_build
          @build_thread&.kill
          @step_thread&.kill
          notify_stopped(status)
        end

        private

        def poll_build
          # TODO: Start fetching the build periodically
          @build_thread = Thread.new do
            loop do
              update_build
              sleep 5
             end
           end
        end

        def update_build
          build = CircleCI::CLI::Response::Build.get(@build.username, @build.reponame, @build.build_number)

          def on_new_step(step)
            # step_watcher.start()

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
            # step_watcher.stop()

            return if @verbose
            case step.status
            when 'success'
              puts "\e[1A\e[2K\r#{Printer.colorize_green(step.name)}"
            when 'failed'
              puts "\e[1A\e[2K\r#{Printer.colorize_red(step.name)}"
              @messages[step].each(&method(:say))
            end
          end

          # Calc actions diff and dispatch event
          build.steps
               .each { |step|
                 on_new_step(step) unless @steps.any? { |s| s.name == step.name }
                 on_new_step_status(step) if @steps.any? { |s| s.name == step.name && s.status != step.status }
               }

          @steps = build.steps
        end

#        def step_watcher(step)
#          @step_thread = Thread.new do
#            loop do
#              response = Faraday.new(
#                "https://circleci.com/api/private/output/raw/github/#{@build.org}/#{@build.repo}/#{@build.number}/output//#{step.actions.step}"
#              ).get.body
#              active_step =
#              if !response.empty?
#                if @verbose
#                  Thor::Shell::Basic.new.say(json['out']['message'], nil, false)
#                else
#                  @messages[json['step']] << json['out']['message']
#                end
#              end
#
#              sleep 1
#            end
#          end
#        end

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
