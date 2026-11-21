# frozen_string_literal: true

module CircleCI
  module CLI
    module Networking
      # The circleci gem adds its configured token when building the request URI.
      module CircleCIRequestAuthentication
        private

        def build_uri(path, params = {})
          query = params.reject { |key, _| key.to_s == 'circle-token' }
          uri = @config.uri
          uri.path += path
          uri.query = URI.encode_www_form(query) unless query.empty?
          uri
        end

        def connection(verb, body = {})
          super.tap { |request| request['Circle-Token'] = @config.token }
        end
      end
    end
  end
end

CircleCi::Request.prepend(CircleCI::CLI::Networking::CircleCIRequestAuthentication)
