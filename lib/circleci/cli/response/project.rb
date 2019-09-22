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
          CircleCi::Projects.new.get.body.map { |p| Project.new(p) }
        end
      end
    end
  end
end
