# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class BuildsCommand < BaseCommand
        class << self
          def run(options)
            setup_token
            project_name = project_name(options)
            username, reponame = project_name.split('/')
            branch = branch_name(options)
            builds = if branch
                       Response::Build.branch(username, reponame, branch)
                     else
                       Response::Build.all(username, reponame)
                     end

            say Printer::BuildPrinter.new(builds, project_name, pretty: options.pretty).to_s
          end
        end
      end
    end
  end
end
