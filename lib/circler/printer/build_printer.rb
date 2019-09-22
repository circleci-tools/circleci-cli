# frozen_string_literal: true

module Circler
  class BuildPrinter
    def initialize(builds, pretty: true)
      @builds = builds
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
      Terminal::Table.new(title: title, headings: headings, rows: rows).to_s
    end

    def title
      build = @builds.first
      "Recent Builds / #{build.project_name}".green
    end

    def headings
      %w[Number Status Branch Author Commit Duration StartTime]
    end

    def rows
      @builds.map(&:information)
    end

    def max_row_widths
      @builds
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
