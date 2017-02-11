module Circler
  class WatchCommand < BaseCommand
    class << self
      def run(options)
        setup_token

        build = get_build(options)

        if !build.nil? && build.running?
          say 'Connecting to pusher'.blue
          setup_client
          say 'Connected'.blue

          start_watch(build)
          wait_until_finish
          finalize(build, build.channel_name)
        else
          say 'The build is not running'
        end
      end

      private

      def setup_client()
        @@client = CirclerPusherClient.new
        @@client.connect
      end

      def get_build(options)
        username, reponame = project_name(options).split('/')
        number = options.build || ask('Input build number')
        Build.get(username, reponame, number)
      end

      def start_watch(build)
        @@running = true
        print_bordered "Start watching #{build.username}/#{build.reponame} build ##{build.build_number}".blue
        TerminalNotifier.notify("Start to build #{build.username}/#{build.reponame} build ##{build.build_number}")

        bind_event_handling(build.channel_name)
      end

      def bind_event_handling(channel)
        @@client.bind(channel, 'newAction') do |data|
          JSON.parse(data).each do |d|
            print_bordered d['log']['name'].green
          end
        end

        @@client.bind(channel, 'appendAction') do |data|
          JSON.parse(data).each { |d| say d['out']['message'] }
        end

        @@client.bind(channel, 'updateAction') do |data|
          JSON.parse(data).each do |d|
            @@running = d['log']['name'] != 'Disable SSH'
          end
        end
      end

      def wait_until_finish
        while @@running
          sleep(1)
        end
      end

      def finalize(build, channel)
        @@client.unsubscribe(channel)

        print_bordered "Finish watching #{build.username}/#{build.reponame} build ##{build.build_number}".blue
        TerminalNotifier.notify("Finish building #{build.username}/#{build.reponame} build ##{build.build_number}")
      end

      def print_bordered(text)
        say Terminal::Table.new(
          rows: [[text]],
          style: { width: 120 }
        ).to_s
      end
    end
  end
end
