# frozen_string_literal: true

module CircleCI
  module CLI
    module Response
      class Project
        def self.all
          Response.body!(CircleCi::Projects.new.get)
                  .select { |project| %r{\Ahttps?://github\.com/}i.match?(project['vcs_url'].to_s) }
                  .map { |project| new(project) }
        end

        def initialize(hash)
          @hash = hash
        end

        def information
          [@hash['username'], @hash['reponame']]
        end
      end
    end
  end
end
