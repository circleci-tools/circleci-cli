module Circler
  class CancelCommand < BaseCommand
    class << self
      def run(options)
        setup_token
        username, reponame = project_name(options).split('/')
        number = build_number(options)
        build = Build.cancel(username, reponame, number)
        if build.username
          say "build #{build.username}/#{build.reponame} #{build.build_number} is canceled."
        else
          say "failed to cancel #{username}/#{reponame} #{number}."
        end
      end
    end
  end
end
