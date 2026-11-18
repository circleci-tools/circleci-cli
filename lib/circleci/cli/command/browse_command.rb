# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class BrowseCommand < BaseCommand
        class << self
          def run(options)
            setup_token
            project = project_name(options)
            number = build_number(options, prompt: false)
            Launchy.open url(project, number)
          end

          def url(project, number)
            return "https://circleci.com/gh/#{project}" unless number

            "https://circleci.com/gh/#{project}/#{number}"
          end
        end
      end
    end
  end
end
