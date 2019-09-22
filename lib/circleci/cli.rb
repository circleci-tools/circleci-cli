# frozen_string_literal: true

require 'thor'
require 'faraday'
require 'launchy'
require 'terminal-table'
require 'highline/import'
require 'colorize'
require 'rugged'
require 'circleci'
require 'terminal-notifier'

require 'circleci/cli/version'
require 'circleci/cli/command'
require 'circleci/cli/response'
require 'circleci/cli/printer'
require 'circleci/cli/networking'

module CircleCI
  module CLI
    class Runner < Thor
      desc 'projects', 'list projects'
      method_option :format, aliases: 'f', type: :string, banner: 'pretty/simple'
      def projects
        Command::ProjectsCommand.run(options)
      end

      desc 'builds', 'list builds'
      method_option :project, aliases: 'p', type: :string, banner: 'user/project'
      method_option :branch, aliases: 'b', type: :string, banner: 'some-branch'
      method_option :format, aliases: 'f', type: :string, banner: 'pretty/simple'
      def builds
        Command::BuildsCommand.run(options)
      end

      desc 'build', 'show build description'
      method_option :project, aliases: 'p', type: :string, banner: 'user/project'
      method_option :build, aliases: 'n', type: :numeric, banner: 'build-number'
      def build
        Command::BuildCommand.run(options)
      end

      desc 'browse', 'open circle ci website'
      method_option :project, aliases: 'p', type: :string, banner: 'user/project'
      method_option :build, aliases: 'n', type: :numeric, banner: 'build-number'
      def browse
        Command::BrowseCommand.run(options)
      end

      desc 'retry', 'retry a build'
      method_option :project, aliases: 'p', type: :string, banner: 'user/project'
      method_option :build, aliases: 'n', type: :numeric, banner: 'build-number'
      def retry
        Command::RetryCommand.run(options)
      end

      desc 'cancel', 'cancel a build'
      method_option :project, aliases: 'p', type: :string, banner: 'user/project'
      method_option :build, aliases: 'n', type: :numeric, banner: 'build-number'
      def cancel
        Command::CancelCommand.run(options)
      end

      desc 'watch', 'watch a build in real time'
      method_option :project, aliases: 'p', type: :string, banner: 'user/project'
      method_option :build, aliases: 'n', type: :numeric, banner: 'build-number'
      def watch
        Command::WatchCommand.run(options)
      end

      desc 'version', 'show gem version'
      def version
        say CircleCI::CLI::VERSION
      end
    end
  end
end
