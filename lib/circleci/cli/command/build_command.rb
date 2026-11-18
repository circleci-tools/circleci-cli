# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class BuildCommand < BaseCommand
        class << self
          def run(options)
            setup_token
            username, reponame = project_name(options).split('/')
            number = build_number_for(username, reponame, options)
            return say 'No failed build found.' if options.last && number.nil?

            build = Response::Build.get(username, reponame, number)
            puts Printer::StepPrinter.new(build.steps, pretty: options.pretty)
          end

          private

          def build_number_for(username, reponame, options)
            number = build_number(options, prompt: !options.last)
            return number unless options.last

            Response::Build.failed(username, reponame).map(&:build_number).max
          end
        end
      end
    end
  end
end
