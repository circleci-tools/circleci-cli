module Circler
  class BuildPrinter
    def initialize(builds, compact: false)
      @builds = builds
      @compact = compact
    end

    def to_s
      if @compact
        max_row_widths = max_row_widths(@builds)
        @builds.map(&:information)
          .map { |array| array.map.with_index { |column, index| column.to_s + ' ' * (max_row_widths[index] - column.to_s.size) }.join('  ').to_s }
          .join("\n")
      else
        Terminal::Table.new(title: title, headings: headings, rows: rows).to_s
      end
    end

    private

    def title
      "Recent Builds / #{@builds.first.username}/#{@builds.first.reponame}".green
    end

    def headings
      ['Number', 'Status', 'Branch', 'Author', 'Commit', 'Duration', 'Start time']
    end

    def rows
      @builds.map(&:information)
    end

    def max_row_widths(builds)
      builds.map(&:information)
          .map { |array| array.map(&:to_s).map(&:size) }
          .transpose
          .map(&:max)
    end
  end
end
