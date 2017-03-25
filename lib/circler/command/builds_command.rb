module Circler
  class BuildsCommand < BaseCommand
    class << self
      def run(options)
        setup_token
        username, reponame = project_name(options).split('/')

        builds =
          if options.branch
            Build.branch(username, reponame, options.branch)
          else
            Build.all(username, reponame)
          end

        say BuildPrinter.new(builds, pretty: should_be_pretty(options))
      end
    end
  end
end
