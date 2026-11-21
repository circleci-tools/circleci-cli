# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class RetryCommand < BaseCommand
        class << self
          def run(options)
            setup_token
            username, reponame = project_target(options)
            with_build_number(username, reponame, options) { |number| retry_build(username, reponame, number) }
          end

          private

          def retry_build(username, reponame, number)
            build = Response::Build.retry(username, reponame, number)

            if build&.username
              puts "build #{username}/#{reponame} #{build.build_number} is triggered"
            else
              puts "failed to trigger #{username}/#{reponame} #{number}"
            end
          end
        end
      end
    end
  end
end
