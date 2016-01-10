require 'thor'
require 'faraday'
require 'terminal-table'
require 'highline/import'
require 'colorize'
require 'rugged'
require 'circleci'
require 'circle'
require 'circle/command/base_command'
require 'circle/command/projects_command'
require 'circle/command/builds_command'
require 'circle/command/build_command'
require 'circle/response/project'
require 'circle/response/build'
require 'circle/response/step'
require 'circle/printer/project_printer'
require 'circle/printer/build_printer'
require 'circle/printer/step_printer'

module Circle
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

    desc 'version', 'show gem version'
    def version
      say Circle::VERSION
    end
  end
end
