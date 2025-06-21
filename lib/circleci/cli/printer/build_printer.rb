# frozen_string_literal: true

module CircleCI
  module CLI
    module Printer
      class BuildPrinter
        class << self
          def header_for(build, title)
            texts = [
              ["Project:  #{build.project_name}"],
              ["Build:    #{build.build_number}"],
              ["Author:   #{build.author_name}"],
              ["Workflow: #{build.workflow_name}/#{build.workflow_job_name}"]
            ]
            Terminal::Table.new(title:, rows: texts, style: { width: 120 }).to_s
          end
        end

        def initialize(builds, project_name, pretty: true)
          @builds_to_show = builds
          @project_name = project_name
          @pretty = pretty
        end

        def to_s
          @pretty ? print_pretty : print_compact
        end

        private

        def print_compact
          rows.map { |row| pad_columns_by_space(row, max_row_widths) }.join("\n")
        end

        def print_pretty
          Terminal::Table.new(title:, headings:, rows:).to_s
        end

        def title
          Printer.colorize_green("Recent Builds / #{@project_name}")
        end

        def headings
          %w[Number Status Branch Author Commit Duration StartTime]
        end

        def rows
          @builds_to_show.map(&:information)
        end

        def max_row_widths
          @builds_to_show
            .map(&:information)
            .map { |array| array.map(&:to_s).map(&:size) }
            .transpose
            .map(&:max)
        end

        def pad_columns_by_space(columns, max_widths)
          columns
            .map
            .with_index { |column, i| pad_column_by_space(column, max_widths, i) }
            .join('  ')
            .to_s
        end

        def pad_column_by_space(column, max_widths, index)
          column_string = column.to_s
          spaces = ' ' * (max_widths[index] - column_string.size)
          column_string + spaces
        end
      end
    end
  end
end
