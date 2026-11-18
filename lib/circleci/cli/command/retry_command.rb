# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class RetryCommand < BaseCommand
        class << self
          def run(options)
            setup_token
            username, reponame = project_name(options).split('/')
            number = build_number_for(username, reponame, options)
            return say 'No failed build found.' if options.last && number.nil?

            build = Response::Build.retry(username, reponame, number)

            if build&.username
              puts "build #{username}/#{reponame} #{build.build_number} is triggered"
            else
              puts "failed to trigger #{username}/#{reponame} #{number}"
            end
          end

          private

          def build_number_for(username, reponame, options)
            number = build_number(options, prompt: !options.last)
            return number unless options.last

            Response::Build.failed(username, reponame).map(&:build_number).max
          end
        end
      end
    end
  end
end
