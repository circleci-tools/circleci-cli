# frozen_string_literal: true

module CircleCI
  module CLI
    module Printer
      class BuildPrinter
        class << self
          def header_for(build, title)
            texts = [
              "Project:  #{build.project_name}",
              "Build:    #{build.build_number}",
              "Author:   #{build.author_name}",
              "Workflow: #{build.workflow_name}/#{build.workflow_job_name}"
            ]
            rows = texts.map { |text| [Printer.escape_controls(text)] }
            Terminal::Table.new(title: Printer.escape_controls(title), rows:, style: { width: 120 }).to_s
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
          build_rows = rows
          max_widths = max_row_widths(build_rows)
          build_rows.map { |row| pad_columns_by_space(row, max_widths) }.join("\n")
        end

        def print_pretty
          Terminal::Table.new(title:, headings:, rows:).to_s
        end

        def title
          Printer.colorize_green("Recent Builds / #{Printer.escape_controls(@project_name)}")
        end

        def headings
          %w[Number Status Branch Author Commit Duration StartTime]
        end

        def rows
          @builds_to_show.map { |build| row_for(build) }
        end

        def row_for(build)
          status = Printer.escape_controls(build.status)
          branch = Printer.escape_controls(build.branch)
          [
            Printer.escape_controls(build.build_number),
            Printer.colorize_by_status(status, status),
            Printer.colorize_by_status(branch, status),
            *build_details(build)
          ]
        end

        def build_details(build)
          [
            build.author_name,
            (build.subject || '').slice(0..60),
            Printer.format_duration(build.build_time_millis),
            build.start_time
          ].map { |value| Printer.escape_controls(value) }
        end

        def max_row_widths(build_rows)
          build_rows
            .map { |row| row.map { |column| column_width(column) } }
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
          spaces = ' ' * (max_widths[index] - column_width(column_string))
          column_string + spaces
        end

        def column_width(column)
          Unicode::DisplayWidth.of(column.to_s.gsub(/\e\[[\d;]*m/, ''))
        end
      end
    end
  end
end
