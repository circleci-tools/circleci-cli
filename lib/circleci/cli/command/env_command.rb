# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class EnvCommand < Thor
        class << self
          def exit_on_failure?
            true
          end
        end

        desc 'list', "List a project's environment variables"
        method_option :project,
                      aliases: 'p',
                      type: :string,
                      banner: 'user/project',
                      desc: 'A project you want to get.'
        method_option :pretty, type: :boolean, default: true, desc: 'Make output pretty.'
        def list
          username, reponame = project_target
          env_vars = Response::EnvVar.all(username, reponame)
          puts Printer::EnvVarPrinter.new(env_vars, "#{username}/#{reponame}", pretty: options.pretty)
        end

        desc 'set NAME VALUE', "Set a project's environment variable"
        method_option :project,
                      aliases: 'p',
                      type: :string,
                      banner: 'user/project',
                      desc: 'A project you want to get.'
        def set(name, value)
          username, reponame = project_target
          Response::EnvVar.set(username, reponame, name, value)
          puts "#{name} is set for #{username}/#{reponame}."
        end

        desc 'delete NAME', "Delete a project's environment variable"
        method_option :project,
                      aliases: 'p',
                      type: :string,
                      banner: 'user/project',
                      desc: 'A project you want to get.'
        def delete(name)
          username, reponame = project_target
          Response::EnvVar.delete(username, reponame, name)
          puts "#{name} is deleted for #{username}/#{reponame}."
        end

        private

        def project_target
          BaseCommand.setup_token
          defaults = {}
          defaults[:project] = Runner.project(validate_on_dispatch: true) unless options.key?(:project)
          BaseCommand.project_target(options.merge(defaults))
        end
      end
    end
  end
end
