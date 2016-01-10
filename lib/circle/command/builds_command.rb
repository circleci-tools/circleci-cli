module Circle
  class BuildsCommand < BaseCommand
    class << self
      def run(options)
        setup_token
        username, reponame = project_name(options).split('/')

        if options.branch
          builds = Build.branch(username, reponame, options.branch)
        else
          builds = Build.all(username, reponame)
        end

        say BuildPrinter.new(builds)
      end
    end
  end
end
