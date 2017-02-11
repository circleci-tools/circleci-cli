module Circler
  class BaseCommand
    class << self
      def setup_token()
        CircleCi.configure do |config|
          config.token = ENV['CIRCLE_CI_TOKEN'] || ask('Circle CI token ? :')
        end
      end

      def project_name(options)
        if options.project
          options.project
        elsif self.reponame
          self.reponame
        else
          say ProjectPrinter.new(Project.all)
          ask('Input user-name/project-name :')
        end
      end

      def reponame
        repository = Rugged::Repository.new('.')
        origin = repository.remotes.find { |r| r.name == 'origin' }
        return $1 if origin.url =~ %r{git@github.com:([\w_-]+/[\w_-]+)\.git}
        nil
      end

      def build_number(options)
        options.build || ask('Input build number')
      end
    end
  end
end
