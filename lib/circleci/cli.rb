# frozen_string_literal: true

require 'circleci'

require 'highline/import'
require 'launchy'
require 'rugged'
require 'terminal-notifier'
require 'terminal-table'
require 'thor'
require 'uri'

require 'circleci/cli/version'
require 'circleci/cli/command'
require 'circleci/cli/response'
require 'circleci/cli/printer'
require 'circleci/cli/networking/http_client'
require 'circleci/cli/networking/circleci_request_authentication'
require 'circleci/cli/networking'

module CircleCI
  module CLI
    class Runner < Thor # rubocop:disable Metrics/ClassLength
      package_name 'circleci-cli'

      class << self
        def exit_on_failure?
          true
        end

        def project(validate_on_dispatch: false)
          repository = Rugged::Repository.discover('.')
          origin = repository.remotes.find { |r| r.name == 'origin' }
          github_project(origin.url, validate_on_dispatch:) if origin&.url
        rescue Rugged::RepositoryError
          nil
        end

        def branch_name
          repository = Rugged::Repository.discover('.')
          head = repository.head

          return nil unless head.branch?

          head.name.sub(%r{\Arefs/heads/}, '')
        rescue Rugged::RepositoryError, Rugged::ReferenceError
          nil
        end

        private

        def github_project(remote, validate_on_dispatch:)
          path = github_remote_path(remote)&.delete_suffix('.git')
          return path&.delete_prefix('/') if validate_on_dispatch

          return unless path&.match?(%r{\A/[\w-]+/[.\w-]+\z})
          return if %w[. ..].include?(File.basename(path))

          path.delete_prefix('/')
        end

        def github_remote_path(remote)
          scp = /\Agit@github\.com:(.+)\z/i.match(remote)
          return "/#{scp[1]}" if scp

          uri = URI.parse(remote)
          return if uri.query || uri.fragment

          uri.path if github_uri?(uri)
        rescue URI::InvalidURIError
          nil
        end

        def github_uri?(uri)
          case uri.host&.downcase
          when 'github.com' then uri.scheme == 'https' || github_ssh_uri?(uri)
          when 'ssh.github.com' then uri.port == 443 && github_ssh_uri?(uri)
          else false
          end
        end

        def github_ssh_uri?(uri)
          uri.scheme == 'ssh' && uri.userinfo == 'git'
        end
      end

      desc 'projects', 'List projects'
      method_option :pretty, type: :boolean, default: true, desc: 'Make output pretty'
      def projects
        Command::ProjectsCommand.run(options)
      end

      desc 'builds', 'List builds'
      method_option :project,
                    aliases: 'p',
                    type: :string,
                    banner: 'user/project',
                    desc: 'A project you want to get.'
      method_option :branch,
                    aliases: 'b',
                    type: :string,
                    banner: 'some-branch',
                    desc: 'A branch name you want to filter with.'
      method_option :all,
                    aliases: 'a',
                    type: :boolean,
                    default: false,
                    desc: 'Target all the branches. This option overwrites branch option.'
      method_option :pretty, type: :boolean, banner: 'true/false', default: true, desc: 'Make output pretty.'
      def builds
        Command::BuildsCommand.run(git_options(infer_branch: true))
      end

      desc 'run RUN_ID', 'Show all workflows and jobs in a run'
      method_option :failed_tests, type: :boolean, desc: 'Show failed tests grouped by workflow and job'
      map 'run' => :show_run
      def show_run(run_id)
        say Command::RunCommand.run(run_id, failed_tests: options[:failed_tests])
      end

      desc 'artifacts RUN_ID', 'List or download artifacts from a run'
      method_option :download, type: :string, banner: 'PATH', desc: 'Download artifacts matching this path glob'
      method_option :destination, type: :string, banner: 'DIRECTORY', desc: 'Save matching artifacts in this directory'
      def artifacts(run_id)
        say Command::ArtifactsCommand.run(run_id, download: options[:download], destination: options[:destination])
      end

      desc 'build', 'Show the build result'
      method_option :project,
                    aliases: 'p',
                    type: :string,
                    banner: 'user/project',
                    desc: 'A project you want to get.'
      method_option :build, aliases: 'n', type: :string, banner: 'build-number', desc: 'Build number you want to get.'
      method_option :last, aliases: 'l', type: :boolean, default: false, desc: 'Get last failed build.'
      method_option :pretty, type: :boolean, banner: 'true/false', default: true, desc: 'Make output pretty.'
      def build
        Command::BuildCommand.run(git_options)
      end

      desc 'browse', 'Open CircleCI website'
      method_option :project,
                    aliases: 'p',
                    type: :string,
                    banner: 'user/project',
                    desc: 'A project you want to get.'
      method_option :build,
                    aliases: 'n',
                    type: :string,
                    banner: 'build-number',
                    desc: 'Build number you want to browse.'
      def browse
        Command::BrowseCommand.run(git_options)
      end

      desc 'retry', 'Retry a build'
      method_option :project,
                    aliases: 'p',
                    type: :string,
                    banner: 'user/project',
                    desc: 'A project you want to get.'
      method_option :build,
                    aliases: 'n',
                    type: :string,
                    banner: 'build-number',
                    desc: 'Build number you want to retry.'
      method_option :last, aliases: 'l', type: :boolean, desc: 'Retry last failed build.'
      def retry
        Command::RetryCommand.run(git_options)
      end

      desc 'cancel', 'Cancel a build'
      method_option :project,
                    aliases: 'p',
                    type: :string,
                    desc: 'A project you want to get.'
      method_option :build,
                    aliases: 'n',
                    type: :string,
                    banner: 'build-number',
                    desc: 'Build number you want to cancel.'
      def cancel
        Command::CancelCommand.run(git_options)
      end

      desc 'watch', 'Watch builds in real time'
      method_option :project,
                    aliases: 'p',
                    type: :string,
                    banner: 'user/project',
                    desc: 'A project you want to get.'
      method_option :branch,
                    aliases: 'b',
                    type: :string,
                    banner: 'some-branch',
                    desc: 'A branch name you want to filter with.'
      method_option :all,
                    aliases: 'a',
                    type: :boolean,
                    default: false,
                    desc: 'Target all the branches. This option overwrites branch option.'
      method_option :user, aliases: 'u', type: :string, banner: 'user'
      method_option :verbose,
                    aliases: 'v',
                    type: :boolean,
                    default: false,
                    desc: 'Show all the build logs including successful build steps.'
      def watch
        Command::WatchCommand.run(git_options(infer_branch: true))
      end

      desc 'version', 'Show gem version'
      def version
        say CircleCI::CLI::VERSION
      end

      private

      def git_options(infer_branch: false)
        defaults = {}
        defaults[:project] = self.class.project(validate_on_dispatch: true) unless options.key?(:project)
        defaults[:branch] = self.class.branch_name if infer_branch && !options[:all] && !options.key?(:branch)
        options.merge(defaults)
      end
    end
  end
end
