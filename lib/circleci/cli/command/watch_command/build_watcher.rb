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
        end

        def start
          bind_event_handling @build.channel_name
          notify_started
        end

        def stop(status)
          client.unsubscribe("#{@build.channel_name}@0")
          notify_stopped(status)
        end

        private

        def bind_event_handling(channel) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          client.bind_event_json(channel, 'newAction') do |json|
            if @verbose
              print_bordered json['log']['name']
            else
              print json['log']['name']
            end
          end

          client.bind_event_json(channel, 'appendAction') do |json|
            if @verbose
              Thor::Shell::Basic.new.say(json['out']['message'], nil, false)
            else
              @messages[json['step']] << json['out']['message']
            end
          end

          client.bind_event_json(channel, 'updateAction') do |json|
            next if @verbose

            case json['log']['status']
            when 'success'
              puts "\e[2K\r#{Printer.colorize_green(json['log']['name'])}"
            when 'failed'
              puts "\e[2K\r#{Printer.colorize_red(json['log']['name'])}"
              @messages[json['step']].each(&method(:say))
            end
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

        def client
          @client ||= Networking::CircleCIPusherClient.new.tap(&:connect)
        end
      end
    end
  end
end
