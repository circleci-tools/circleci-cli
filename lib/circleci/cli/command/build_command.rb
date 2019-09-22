# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class BuildCommand < BaseCommand
        class << self
          def run(options)
            setup_token
            username, reponame = project_name(options).split('/')
            number = build_number(options)
            build = Response::Build.get(username, reponame, number)
            say Printer::StepPrinter.new(build.steps).to_s
          end
        end
      end
    end
  end
end
