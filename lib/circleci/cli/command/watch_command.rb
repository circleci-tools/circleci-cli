# frozen_string_literal: true

require 'circleci/cli/command/watch_command/build_repository'
require 'circleci/cli/command/watch_command/build_watcher'

module CircleCI
  module CLI
    module Command
      class WatchCommand < BaseCommand
        def self.run(options)
          token = setup_token
          username, reponame = project_name(options).split('/')
          repository = BuildRepository.new(username, reponame, branch: branch_name(options), user: options.user)
          new(options, repository).run(token)
        rescue Interrupt
          say 'Exited'
        end

        def initialize(options, repository)
          super()
          @options = options
          @repository = repository
          @refresh_lock = Mutex.new
          @refresh_pending = false
        end

        def run(token)
          client = Networking::CircleCIPusherClient.new(token:)
          client.connect
          channel = "private-#{Response::Account.me.pusher_id}"
          client.bind(channel, 'call') do
            @refresh_lock.synchronize { @refresh_pending = true }
          end
          watch_builds
        ensure
          release_subscription(client, channel) if client
        end

        private

        def release_subscription(client, channel)
          client.unsubscribe(channel) if channel
        ensure
          client.disconnect
        end

        def watch_builds
          loop do
            refresh_builds_if_needed
            stop_existing_watcher_if_needed
            start_watcher_if_needed
            sleep 1
          end
        ensure
          @build_watcher&.close
          @build_watcher = nil
        end

        def refresh_builds_if_needed
          pending = @refresh_lock.synchronize do
            pending_refresh = @refresh_pending
            @refresh_pending = false
            pending_refresh
          end
          @repository.update if pending
        end

        def stop_existing_watcher_if_needed
          return if @build_watcher.nil?

          build = @repository.build_for(@build_watcher.build.build_number, recent_only: true) ||
                  @build_watcher.latest_detail
          return if build.nil? || !build.finished?

          @build_watcher.stop(build.status)
          @repository.mark_as_shown(build.build_number)
          @build_watcher = nil
        end

        def start_watcher_if_needed
          return unless @build_watcher.nil?

          builds = @repository.builds_to_show
          return if builds.empty?

          candidate = builds.find { |build| !build.finished? && build.running? }
          build_to_watch = @repository.watch(candidate.build_number) if candidate
          show_interrupted_build_results
          return unless build_to_watch

          @build_watcher = BuildWatcher.new(build_to_watch, verbose: @options.verbose)
          @build_watcher.start
        end

        def show_interrupted_build_results # rubocop:disable Metrics/AbcSize
          @repository.builds_to_show.select(&:finished?).each do |build|
            b = Response::Build.get(build.username, build.reponame, build.build_number)
            title = "✅ Result of #{build.project_name} ##{build.build_number} completed in background"
            puts Printer::BuildPrinter.header_for(build, title)
            puts Printer::StepPrinter.new(b.steps, pretty: @options.verbose)
            @repository.mark_as_shown(b.build_number)
          end
        end
      end
    end
  end
end
