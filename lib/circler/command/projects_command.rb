module Circler
  class ProjectsCommand < BaseCommand
    class << self
      def run(options)
        setup_token
        say ProjectPrinter.new(Project.all, compact: options['format'] == 'simple')
      end
    end
  end
end
