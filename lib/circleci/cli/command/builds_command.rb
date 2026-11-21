# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class BuildsCommand < BaseCommand
        class << self
          def run(options)
            setup_token
            username, reponame = project_target(options)
            branch = branch_name(options)
            builds = if branch
                       Response::Build.branch(username, reponame, branch)
                     else
                       Response::Build.all(username, reponame)
                     end

            puts Printer::BuildPrinter.new(builds, "#{username}/#{reponame}", pretty: options.pretty)
          end
        end
      end
    end
  end
end
