# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class BaseCommand
        class << self
          def setup_token
            token = ENV.fetch('CIRCLE_CI_TOKEN', nil) || ask('Circle CI token ? :') { |question| question.echo = false }
            CircleCi.configure { |config| config.token = token }
            token
          end

          def project_target(options)
            project = options.project || prompt_project
            match = %r{\A([\w-]+)/([.\w-]+)\z}.match(project)
            return match.captures if match && !%w[. ..].include?(match[2])

            raise Thor::Error, 'Project must be in owner/repo format.'
          end

          def branch_name(options)
            if options.all
              nil
            else
              options.branch
            end
          end

          def build_number(options, prompt: true)
            number = options.build
            return nil if number.nil? && !prompt

            number = ask('Input build number') if number.nil?
            text = number.to_s
            return text.to_i if text.match?(/\A\+?0*[1-9][0-9]*\z/)

            raise Thor::Error, 'Build number must be a positive integer.'
          end

          private

          def prompt_project
            puts Printer::ProjectPrinter.new(Response::Project.all)
            ask('Input user-name/project-name :')
          end

          def with_build_number(username, reponame, options)
            number = build_number(options, prompt: !options.last)
            return yield number unless options.last

            number = Response::Build.failed(username, reponame).map(&:build_number).max
            return say 'No failed build found.' if number.nil?

            yield number
          end
        end
      end
    end
  end
end
