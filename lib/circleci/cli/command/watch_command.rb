# frozen_string_literal: true

require 'circleci/cli/command/watch_command/build_repository'
require 'circleci/cli/command/watch_command/build_watcher'

module CircleCI
  module CLI
    module Command
      class WatchCommand < BaseCommand
        class << self
          def run(options) # rubocop:disable Metrics/MethodLength
            setup_token

            username, reponame = project_name(options).split('/')
            @options = options
            @repository = BuildRepository.new(
              username,
              reponame,
              branch: branch_name(options),
              user: options.user
            )
            @client = Networking::CircleCIPusherClient.new.tap(&:connect)
            @build_watcher = nil

            bind_status_event

            loop do
              stop_existing_watcher_if_needed
              start_watcher_if_needed
              sleep 1
            end
          rescue Interrupt
            say 'Exited'
          end

          private

          def bind_status_event
            @client.bind("private-#{Response::Account.me.pusher_id}", 'call') { @repository.update }
          end

          def stop_existing_watcher_if_needed
            return if @build_watcher.nil?

            build = @repository.build_for(@build_watcher.build.build_number)
            return if build.nil? || !build.finished?

            @build_watcher.stop(build.status)
            @build_watcher = nil
            show_interrupted_build_results
          end

          def start_watcher_if_needed
            build_to_watch = @repository.builds_to_show.select(&:running?).first
            return unless build_to_watch && @build_watcher.nil?

            show_interrupted_build_results
            @repository.mark_as_shown(build_to_watch.build_number)
            @build_watcher = BuildWatcher.new(build_to_watch, verbose: @options.verbose)
            @build_watcher.start
          end

          def show_interrupted_build_results # rubocop:disable Metrics/AbcSize
            @repository.builds_to_show.select(&:finished?).each do |build|
              b = Response::Build.get(build.username, build.reponame, build.build_number)
              title = "✅ Result of #{build.project_name} ##{build.build_number} completed in background"
              say Printer::BuildPrinter.header_for(build, title)
              say Printer::StepPrinter.new(b.steps, pretty: @options.verbose).to_s
              @repository.mark_as_shown(b.build_number)
            end
          end

          def print_bordered(text)
            say Terminal::Table.new(rows: [[text]], style: { width: 120 }).to_s
          end
        end
      end
    end
  end
end
