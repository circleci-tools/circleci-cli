module Circler
  class Project
    def initialize(hash)
      @hash = hash
    end

    def information
      [@hash['username'], @hash['reponame']]
    end

    def self.all
      CircleCi::Project.all.body.map { |p| Project.new(p) }
    end
  end
end
