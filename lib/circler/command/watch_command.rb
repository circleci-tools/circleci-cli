module Circler
  class WatchCommand < BaseCommand
    class << self
      def run(options)
        setup_token
        say 'Connecting to pusher'.blue

        update_builds(options)
        setup_client(options)

        say 'Connected'.blue

        loop do
          start_watch(@@builds.first) if !@@builds.empty? && !@@running
          sleep 1
        end
      end

      private

      def setup_client(options)
        @@running = false
        @@client = CirclerPusherClient.new
        @@client.connect
        @@client.bind("private-#{Account.me.user_name}", 'call') do
          @@running = false
          update_builds(options)
        end
      end

      def update_builds(options)
        username, reponame = project_name(options).split('/')
        @@builds = Build
          .all(username, reponame)
          .select { |b| b.status == 'running' }
      end

      def start_watch(build)
        @@running = true
        print_bordered "Start watching #{build.username}/#{build.reponame} build ##{build.build_number}".blue

        bind_event_handling(build.channel_name)
        wait_until_finish
        finalize(build, build.channel_name)
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
        @@builds = @@builds.select { |b| b.build_number != build.build_number }
        @@client.unsubscribe(channel)

        print_bordered "Finish watching #{build.username}/#{build.reponame} build ##{build.build_number}".blue
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
