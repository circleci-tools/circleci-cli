# frozen_string_literal: true

require 'io/console'

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

        desc 'set NAME [VALUE]', "Set a project's environment variable"
        long_desc 'Omit VALUE to enter it without echo in a terminal, or pass it through standard input.'
        method_option :project,
                      aliases: 'p',
                      type: :string,
                      banner: 'user/project',
                      desc: 'A project you want to get.'
        def set(name, value = nil)
          value = read_value if value.nil?
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
          unless name.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
            raise Thor::Error, 'Invalid environment variable name. Use letters, digits, and underscores, ' \
                               'starting with a letter or underscore.'
          end

          username, reponame = project_target
          Response::EnvVar.delete(username, reponame, name)
          puts "#{name} is deleted for #{username}/#{reponame}."
        end

        private

        def read_value
          value = $stdin.tty? ? prompt_value : $stdin.read
          raise Thor::Error, 'No environment variable value provided on standard input.' if value.nil? || value.empty?

          value
        end

        def prompt_value
          $stderr.print 'Environment variable value: '
          $stderr.flush
          $stdin.noecho(&:gets)&.chomp
        ensure
          $stderr.puts
        end

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
