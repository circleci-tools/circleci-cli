# frozen_string_literal: true

require 'json'
require 'tempfile'
require 'circleci/cli/command/watch_command/build_repository'
require 'circleci/cli/command/watch_command/build_watcher'
require 'circleci/cli/command/watch_command/request_errors'

module CircleCI
  module CLI
    module Command
      class WatchCommand < BaseCommand # rubocop:disable Metrics/ClassLength
        BACKGROUND_LOG_ATTEMPTS = 2

        def self.run(options)
          token = setup_token
          username, reponame = project_target(options)
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
          channel = "private-#{Response::Account.me.pusher_id}"
          client.bind(channel, 'call', 'pusher_internal:subscription_succeeded') do
            @refresh_lock.synchronize { @refresh_pending = true }
          end
          client.connect
          watch_builds(client)
        ensure
          release_subscription(client, channel) if client
        end

        private

        def release_subscription(client, channel)
          client.unsubscribe(channel) if channel
        ensure
          client.disconnect
        end

        def watch_builds(client)
          loop do
            check_connection(client)
            refresh_builds_if_needed
            stop_existing_watcher_if_needed
            start_watcher_if_needed
            sleep 1
          end
        ensure
          @build_watcher&.close
          @build_watcher = nil
        end

        def check_connection(client)
          error = client.poll_connection_error
          raise Thor::Error, "Pusher connection failed: #{error.message}" if error
        end

        def refresh_builds_if_needed
          pending = @refresh_lock.synchronize do
            pending_refresh = @refresh_pending
            @refresh_pending = false
            pending_refresh
          end
          @repository.update if pending
        rescue *WatchRequestErrors::TRANSIENT
          @refresh_lock.synchronize { @refresh_pending = true }
        end

        def stop_existing_watcher_if_needed
          return if @build_watcher.nil?

          error = @build_watcher.poll_error
          raise error if error

          build = @repository.build_for(@build_watcher.build.build_number, recent_only: true)
          build = @build_watcher.latest_detail unless build&.finished?
          return unless build&.finished?

          @build_watcher.stop(build.status)
          @repository.mark_as_shown(build.build_number)
          @build_watcher = nil
        end

        def start_watcher_if_needed
          build_to_watch = next_build_to_watch
          return unless build_to_watch

          @build_watcher = BuildWatcher.new(build_to_watch, verbose: @options.verbose)
          @build_watcher.start
        end

        def next_build_to_watch
          details = @repository.refresh_evicted_builds do |username, reponame, number|
            fetch_background_details { Response::Build.get(username, reponame, number) }
          end
          builds = @repository.builds_to_show
          show_interrupted_build_results(builds, details)
          return if @build_watcher

          candidate = builds.find do |build|
            !build.finished? && build.running? && details.fetch(build.build_number, true)
          end
          @repository.watch(candidate.build_number) if candidate
        end

        def show_interrupted_build_results(builds, details)
          builds.select(&:finished?).each do |build|
            detail = details.fetch(build.build_number) do
              fetch_background_details { Response::Build.get(build.username, build.reponame, build.build_number) }
            end
            show_background_result(build, detail) if detail
          end
        end

        def show_background_result(build, detail)
          title = "✅ Result of #{build.project_name} ##{build.build_number} completed in background"
          @build_watcher&.disable_step_line_rewrites unless @options.verbose
          puts Printer::BuildPrinter.header_for(build, title)
          verbose = @options.verbose
          Printer::StepPrinter.new(detail.steps, pretty: verbose, verbose: verbose,
                                                 log_reader: method(:read_background_log)).write_to($stdout)
          @repository.mark_as_shown(build.build_number)
        end

        def read_background_log(action)
          Tempfile.create('circleci-watch-log', binmode: true) do |file|
            next unless download_background_log(action, file)

            file.rewind
            file.each_line { |line| yield JSON.parse(line) }
          end
        end

        def download_background_log(action, file, attempts: BACKGROUND_LOG_ATTEMPTS)
          action.each_log_chunk { |chunk| file.puts(JSON.generate(chunk)) }
          true
        rescue *WatchRequestErrors::TRANSIENT
          file.rewind
          file.truncate(0)
          attempts -= 1
          retry if attempts.positive?

          warn "Warning: Could not download log for #{Printer.escape_controls(action.name)}."
          false
        end

        def fetch_background_details
          yield
        rescue *WatchRequestErrors::TRANSIENT
          nil
        end
      end
    end
  end
end
