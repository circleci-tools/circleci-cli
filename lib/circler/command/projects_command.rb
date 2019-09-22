# frozen_string_literal: true

module Circler
  class ProjectsCommand < BaseCommand
    class << self
      def run(options)
        setup_token
        say ProjectPrinter.new(Project.all, pretty: should_be_pretty(options)).to_s
      end
    end
  end
end
