# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class BaseCommand
        class << self
          def setup_token
            CircleCi.configure do |config|
              config.token = ENV['CIRCLE_CI_TOKEN'] || ask('Circle CI token ? :')
            end
          end

          def project_name(options)
            if options.project
              options.project
            elsif reponame
              reponame
            else
              say Printer::ProjectPrinter.new(Response::Project.all).to_s
              ask('Input user-name/project-name :')
            end
          end

          def reponame
            repository = Rugged::Repository.new('.')
            origin = repository.remotes.find { |r| r.name == 'origin' }
            regexp = %r{git@github.com(?::|/)([\w_-]+/[.\w_-]+?)(?:\.git)*$}
            return Regexp.last_match(1) if origin.url =~ regexp

            nil
          end

          def branch_name(options)
            if options.all
              nil
            elsif options.branch
              options.branch
            else
              repository = Rugged::Repository.new('.')
              head = repository.head

              return nil unless head.branch?

              head.name.sub(%r{\Arefs/heads/}, '')
            end
          end

          def build_number(options)
            options.build || ask('Input build number')
          end

          def should_be_pretty(options)
            options.pretty.nil? || options.pretty
          end
        end
      end
    end
  end
end
