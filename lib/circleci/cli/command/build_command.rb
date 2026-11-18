# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class BuildCommand < BaseCommand
        class << self
          def run(options)
            setup_token
            username, reponame = project_name(options).split('/')
            number = build_number(options, prompt: !options.last)
            build =
              if options.last
                get_last_build(username, reponame)
              else
                Response::Build.get(username, reponame, number)
              end
            say Printer::StepPrinter.new(build.steps, pretty: options.pretty).to_s
          end

          private

          def get_last_build(username, reponame)
            builds = Response::Build.failed(username, reponame)
            Response::Build.get(username, reponame, builds.map(&:build_number).max)
          end
        end
      end
    end
  end
end
