# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class WatchCommand < BaseCommand
        class << self
          def run(options)
            setup_token
            setup_client

            build = get_build(options)

            if build&.running?
              start_watch(build)
              wait_until_finish
              finalize(build, build.channel_name)
            else
              say 'The build is not running'
            end
          end

          private

          def setup_client
            @client = Networking::CircleCIPusherClient.new
            @client.connect
          end

          def get_build(options)
            username, reponame = project_name(options).split('/')
            number = build_number options
            Response::Build.get(username, reponame, number)
          end

          def start_watch(build)
            @running = true
            text = "Start watching #{build.project_name} ##{build.build_number}"
            print_bordered text
            TerminalNotifier.notify text

            bind_event_handling build.channel_name
          end

          def bind_event_handling(channel)
            @client.bind_event_json(channel, 'newAction') do |json|
              print_bordered json['log']['name'].green
            end

            @client.bind_event_json(channel, 'appendAction') do |json|
              say json['out']['message']
            end

            @client.bind_event_json(channel, 'updateAction') do |json|
              @running = json['log']['name'] != 'Disable SSH'
            end
          end

          def wait_until_finish
            sleep(1) while @running
          end

          def finalize(build, channel)
            @client.unsubscribe(channel)
            text = "Finish watching #{build.project_name} ##{build.build_number}"
            print_bordered text.blue
            TerminalNotifier.notify text
          end

          def print_bordered(text)
            say Terminal::Table.new(rows: [[text]], style: { width: 120 }).to_s
          end
        end
      end
    end
  end
end
