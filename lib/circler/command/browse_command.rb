module Circler
  class BrowseCommand < BaseCommand
    class << self
      def run(options)
        project = project_name(options)
        number = options.build
        Launchy.open url(project, number)
      end

      def url(project, number)
        return "https://circleci.com/gh/#{project}" unless number
        return "https://circleci.com/gh/#{project}/#{number}"
      end
    end
  end
end
