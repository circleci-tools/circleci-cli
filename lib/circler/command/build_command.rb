module Circler
  class BuildCommand < BaseCommand
    class << self
      def run(options)
        setup_token
        username, reponame = project_name(options).split('/')
        number = build_number(options)
        build = Build.get(username, reponame, number)
        say StepPrinter.new(build.steps)
      end
    end
  end
end
