module Circler
  class ProjectsCommand < BaseCommand
    class << self
      def run(options)
        setup_token
        say ProjectPrinter.new(Project.all)
      end
    end
  end
end
