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
          Response.body!(CircleCi::Projects.new.get)
                  .select { |project| project['vcs_url'].to_s.match?(%r{\Ahttps?://github\.com/}i) }
                  .map { |project| new(project) }
        end
      end
    end
  end
end
