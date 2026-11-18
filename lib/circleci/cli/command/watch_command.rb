# frozen_string_literal: true

require 'circleci/cli/command/watch_command/build_repository'
require 'circleci/cli/command/watch_command/build_watcher'

module CircleCI
  module CLI
    module Command
      class WatchCommand < BaseCommand
        class << self
          def run(options) # rubocop:disable Metrics/MethodLength
            token = setup_token

            username, reponame = project_name(options).split('/')
            @options = options
            @repository = BuildRepository.new(
              username,
              reponame,
              branch: branch_name(options),
              user: options.user
            )
            @client = Networking::CircleCIPusherClient.new(token:).tap(&:connect)
            @build_watcher = nil
            @refresh_lock = Mutex.new
            @refresh_pending = false

            bind_status_event
            watch_builds
          rescue Interrupt
            say 'Exited'
          ensure
            @build_watcher&.close
            @build_watcher = nil
          end

          private

          def watch_builds
            loop do
              refresh_builds_if_needed
              stop_existing_watcher_if_needed
              start_watcher_if_needed
              sleep 1
            end
          end

          def bind_status_event
            @client.bind("private-#{Response::Account.me.pusher_id}", 'call') do
              @refresh_lock.synchronize { @refresh_pending = true }
            end
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

            build = @repository.build_for(@build_watcher.build.build_number)
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
end
