# frozen_string_literal: true

module CircleCI
  module CLI
    module Response
      class Project
        def initialize(hash)
          @hash = hash
        end

        def information
          [@hash['username'], @hash['reponame']]
        end

        def self.all
          Response.body!(CircleCi::Projects.new.get).map { |p| Project.new(p) }
        end
      end
    end
  end
end
