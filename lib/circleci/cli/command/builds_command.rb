# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class BuildsCommand < BaseCommand
        class << self
          def run(options)
            setup_token
            username, reponame = project_name(options).split('/')

            builds =
              if options.branch
                Response::Build.branch(username, reponame, options.branch)
              else
                Response::Build.all(username, reponame)
              end

            say Printer::BuildPrinter.new(builds, pretty: should_be_pretty(options)).to_s
          end
        end
      end
    end
  end
end
