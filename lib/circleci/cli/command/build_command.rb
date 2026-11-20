# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class BuildCommand < BaseCommand
        class << self
          def run(options)
            setup_token
            username, reponame = project_target(options)
            with_build_number(username, reponame, options) do |number|
              build = Response::Build.get(username, reponame, number)
              puts Printer::StepPrinter.new(build.steps, pretty: options.pretty)
            end
          end
        end
      end
    end
  end
end
