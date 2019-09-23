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

            build = Response::Build.retry(username, reponame, number)

            if build&.username
              say "build #{username}/#{reponame} #{build.build_number} is triggered"
            else
              say "failed to trigger #{username}/#{reponame} #{number}"
            end
          end

          private

          def build_number_for(username, reponame, options)
            if options.last
              get_last_build_number(username, reponame)
            else
              build_number(options)
            end
          end

          def get_last_build_number(username, reponame)
            Response::Build.failed(username, reponame).map(&:build_number).max
          end
        end
      end
    end
  end
end
