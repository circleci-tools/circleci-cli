# frozen_string_literal: true

require 'net/http'
require 'json'

module CircleCI
  module CLI
    module Networking
      module HTTPClient
        class Session
          def self.open(max_retries: 0)
            session = new(max_retries:)
            yield session
          ensure
            session&.close
          end

          def initialize(max_retries: 0)
            @max_retries = max_retries
          end

          def get_raw(url, headers = {}, &)
            uri = URI(url)
            request = HTTPClient.get_request(uri, headers)
            connection_for(uri).request(request, &)
          end

          def close
            @http&.finish
          ensure
            @http = nil
          end

          private

          def connection_for(uri)
            return @http if @http && @origin == uri.origin

            close
            @origin = uri.origin
            @http = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https')
            @http.max_retries = @max_retries
            @http
          end
        end

        # One Session per origin, kept alive for the pool's lifetime; a long redirect chain
        # across many origins evicts the least recently used session instead of growing unbounded.
        class SessionPool
          LIMIT = 4

          def self.open(max_retries: 0, limit: LIMIT)
            pool = new(max_retries:, limit:)
            yield pool
          ensure
            pool&.close
          end

          def initialize(max_retries: 0, limit: LIMIT)
            @max_retries = max_retries
            @limit = limit
            @sessions = {}
          end

          def get_raw(url, headers = {}, &)
            session_for(URI(url)).get_raw(url, headers, &)
          end

          def close
            @sessions.each_value(&:close)
          ensure
            @sessions.clear
          end

          private

          def session_for(uri)
            origin = uri.origin
            @sessions[origin] = @sessions.delete(origin) || new_session
          end

          def new_session
            @sessions.shift.last.close if @sessions.size >= @limit
            Session.new(max_retries: @max_retries)
          end
        end

        def self.get_raw(url, headers = {}, &read_response)
          uri = URI(url)
          req = get_request(uri, headers)
          Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.max_retries = 0 if read_response
            http.request(req, &read_response)
          end
        end

        def self.post_form(url, params = {}, headers = {})
          uri = URI(url)
          req = Net::HTTP::Post.new(uri, headers)
          req.set_form_data(params)
          req.basic_auth(uri.user, uri.password) if uri.user && !req['Authorization']
          res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(req) }
          JSON.parse(res.body)
        end

        def self.get_request(uri, headers)
          Net::HTTP::Get.new(uri).tap do |request|
            headers.each { |key, value| request[key] = value }
          end
        end
      end
    end
  end
end
