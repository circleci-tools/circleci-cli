# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class BuildCommand < BaseCommand
        class << self
          def run(options)
            setup_token
            username, reponame = project_name(options).split('/')
            build =
              if options.last
                get_last_build(username, reponame)
              else
                get_build(username, reponame, options)
              end
            say Printer::StepPrinter.new(build.steps, pretty: options.pretty).to_s
          end

          private

          def get_build(username, reponame, options)
            number = build_number(options)
            Response::Build.get(username, reponame, number)
          end

          def get_last_build(username, reponame)
            builds = Response::Build.failed(username, reponame)
            Response::Build.get(username, reponame, builds.map(&:build_number).max)
          end
        end
      end
    end
  end
end
