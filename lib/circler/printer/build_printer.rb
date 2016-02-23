module Circler
  class BuildPrinter
    def initialize(builds, compact: false)
      @builds = builds
      @compact = compact
    end

    def to_s
      if @compact
        @builds.map(&:information)
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
  end
end
