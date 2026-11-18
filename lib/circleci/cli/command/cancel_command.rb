# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class CancelCommand < BaseCommand
        class << self
          def run(options)
            setup_token
            username, reponame = project_name(options).split('/')
            number = build_number(options)
            build = Response::Build.cancel(username, reponame, number)
            if build.username
              puts "build #{build.project_name} #{build.build_number} is canceled."
            else
              puts "failed to cancel #{username}/#{reponame} #{number}."
            end
          end
        end
      end
    end
  end
end
