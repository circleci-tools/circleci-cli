# frozen_string_literal: true

require 'circleci'

require 'highline/import'
require 'launchy'
require 'ostruct'
require 'rugged'
require 'terminal-notifier'
require 'terminal-table'
require 'thor'

require 'circleci/cli/version'
require 'circleci/cli/command'
require 'circleci/cli/response'
require 'circleci/cli/printer'
require 'circleci/cli/networking/http_client'
require 'circleci/cli/networking'

module CircleCI
  module CLI
    class Runner < Thor # rubocop:disable Metrics/ClassLength
      package_name 'circleci-cli'

      class << self
        def exit_on_failure?
          true
        end

        def project
          repository = Rugged::Repository.new('.')
          origin = repository.remotes.find { |r| r.name == 'origin' }
          regexp = %r{(?:git@|https://)github.com(?::|/)([\w_-]+/[.\w_-]+?)(?:\.git)*$}
          return Regexp.last_match(1) if origin&.url =~ regexp

          nil
        rescue Rugged::RepositoryError
          nil
        end

        def branch_name
          repository = Rugged::Repository.new('.')
          head = repository.head

          return nil unless head.branch?

          head.name.sub(%r{\Arefs/heads/}, '')
        rescue Rugged::RepositoryError, Rugged::ReferenceError
          nil
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
      map 'run' => :show_run
      def show_run(run_id)
        say Command::RunCommand.run(run_id)
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
        defaults[:project] = self.class.project unless options.key?(:project)
        defaults[:branch] = self.class.branch_name if infer_branch && !options[:all] && !options.key?(:branch)
        options.merge(defaults)
      end
    end
  end
end
