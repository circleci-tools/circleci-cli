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

          @steps = build.steps
          @current_step = nil
          @read_byte = 0
        end

        def start
          poll_build
          notify_started
        end

        def stop(status)
          update_build
          @build_thread&.kill
          notify_stopped(status)
        end

        private

        def poll_build
          @build_thread = Thread.new do
            count = 0
            loop do
              update_build if (count % 5).zero?
              update_actions

              count += 1
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
            @messages[step.action_identity].each(&method(:say))
          end
        end

        # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        def update_build
          build = CircleCI::CLI::Response::Build.get(@build.username, @build.reponame, @build.build_number)
          previous_statuses = @steps.to_h { |step| [step.action_identity, step.status] }
          steps = build.steps.each do |step|
            status = previous_statuses[step.action_identity]
            next on_new_step(step) unless status

            on_new_step_status(step) unless status == step.status
          end
          @steps = steps

          next_step = steps.find { |step| step.status == 'running' }
          @read_byte = 0 if @current_step&.action_identity != next_step&.action_identity
          @current_step = next_step
        end

        # rubocop:disable-next Metrics/MethodLength
        def update_actions
          return unless @current_step

          identity = @current_step.action_identity
          url = "https://circleci.com/api/private/output/raw/github/#{@build.username}/#{@build.reponame}/#{@build.build_number}/output/#{identity.join('/')}"
          headers = { 'Range' => "bytes=#{@read_byte}-" }
          response = HTTPClient.get(url, headers).body

          return if response.empty?

          @read_byte += response.bytesize

          if @verbose
            Thor::Shell::Basic.new.say(response, nil, false)
          else
            @messages[identity] << response
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
