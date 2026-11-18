# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class ProjectsCommand < BaseCommand
        class << self
          def run(options)
            setup_token
            puts Printer::ProjectPrinter.new(Response::Project.all, pretty: options.pretty)
          end
        end
      end
    end
  end
end
