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
            @messages[step.name].each(&method(:say))
          end
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

          response = Printer.escape_controls(response, multiline: true)
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
          build_label = Printer.escape_controls("#{@build.project_name} ##{@build.build_number}")
          text = case status
                 when 'success'
                   Printer.colorize_green("🎉 #{build_label} has succeeded!")
                 when 'failed'
                   Printer.colorize_red("😥 #{build_label} has failed...")
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
