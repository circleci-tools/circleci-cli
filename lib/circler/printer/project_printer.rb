module Circler
  class ProjectPrinter
    attr_accessor :compact
    def initialize(projects, compact: false)
      @projects = projects
      @compact = compact
    end

    def to_s
      if @compact
        @projects.map(&:information).map { |array| array.join('/').to_s }.sort.join("\n")
      else
        Terminal::Table.new(
          title: 'Projects'.green,
          headings: ['User name', 'Repository name'],
          rows: @projects.map(&:information)
        ).to_s
      end
    end
  end
end
