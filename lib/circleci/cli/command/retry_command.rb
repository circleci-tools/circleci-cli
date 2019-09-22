# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class RetryCommand < BaseCommand
        class << self
          def run(options)
            setup_token
            username, reponame = project_name(options).split('/')
            number = build_number(options)
            build = Response::Build.retry(username, reponame, number)
            if build.username
              say "build #{username}/#{reponame} #{build.build_number} is triggered"
            else
              say "failed to trigger #{username}/#{reponame} #{number}"
            end
          end
        end
      end
    end
  end
end
