require 'thor'
require 'faraday'
require 'launchy'
require 'terminal-table'
require 'highline/import'
require 'colorize'
require 'rugged'
require 'circleci'
require 'circler'
require 'circler/command/base_command'
require 'circler/command/projects_command'
require 'circler/command/builds_command'
require 'circler/command/build_command'
require 'circler/command/browse_command'
require 'circler/command/watch_command'
require 'circler/response/account'
require 'circler/response/project'
require 'circler/response/build'
require 'circler/response/step'
require 'circler/response/action'
require 'circler/printer/project_printer'
require 'circler/printer/build_printer'
require 'circler/printer/step_printer'
require 'circler/networking/pusher_client'

module Circler
  class CLI < Thor
    desc 'projects', 'list projects'
    def projects
      ProjectsCommand.run(options)
    end

    desc 'builds', 'list builds'
    method_option :project, aliases: 'p', type: :string, banner: 'user/project'
    method_option :branch, aliases: 'b', type: :string, banner: 'some-branch'
    def builds
      BuildsCommand.run(options)
    end

    desc 'build', 'show build description'
    method_option :project, aliases: 'p', type: :string, banner: 'user/project'
    method_option :build, aliases: 'n', type: :numeric, banner: 'build-number'
    def build
      BuildCommand.run(options)
    end

    desc 'browse', 'open circle ci website'
    method_option :project, aliases: 'p', type: :string, banner: 'user/project'
    method_option :build, aliases: 'n', type: :numeric, banner: 'build-number'
    def browse
      BrowseCommand.run(options)
    end

    desc 'watch', 'watch a build in real time'
    method_option :project, aliases: 'p', type: :string, banner: 'user/project'
    method_option :build, aliases: 'n', type: :numeric, banner: 'build-number'
    def watch
      WatchCommand.run(options)
    end

    desc 'version', 'show gem version'
    def version
      say Circler::VERSION
    end
  end
end
