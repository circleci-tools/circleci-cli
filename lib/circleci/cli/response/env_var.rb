# frozen_string_literal: true

module CircleCI
  module CLI
    module Response
      class EnvVar
        class << self
          def all(username, reponame)
            response = CircleCi::Project.new(username, reponame, 'github').envvar
            Response.body!(response).map { |hash| EnvVar.new(hash) }
          end

          def set(username, reponame, name, value)
            response = CircleCi::Project.new(username, reponame, 'github').add_envvar(name:, value:)
            EnvVar.new(Response.body!(response))
          end

          def delete(username, reponame, name)
            response = CircleCi::Project.new(username, reponame, 'github').delete_envvar(name)
            Response.body!(response)
          end
        end

        attr_reader :name, :value

        def initialize(hash)
          @name = hash['name']
          @value = hash['value']
        end
      end
    end
  end
end
