# frozen_string_literal: true

module CircleCI
  module CLI
    module Printer
      class ProjectPrinter
        attr_accessor :compact
        def initialize(projects, pretty: true)
          @projects = projects
          @pretty = pretty
        end

        def to_s
          @pretty ? print_pretty : print_compact
        end

        private

        def print_compact
          @projects
            .map(&:information)
            .map { |array| array.join('/').to_s }
            .sort
            .join("\n")
        end

        def print_pretty
          Terminal::Table.new(
            title: 'Projects'.green,
            headings: ['User name', 'Repository name'],
            rows: @projects.map(&:information)
          ).to_s
        end
      end
    end
  end
end
