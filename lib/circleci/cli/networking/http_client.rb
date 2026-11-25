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
        #
        # Safe to share across worker threads: checkout (picking/creating a session) is
        # serialized by a pool-wide mutex, and each origin additionally gets its own mutex so
        # concurrent requests to the *same* origin are serialized onto its one connection while
        # different origins still proceed in parallel. Checkout always marks an origin as most
        # recently used, so eviction can only ever hit an idle origin as long as the number of
        # concurrent callers never exceeds LIMIT.
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
            @locks = {}
            @mutex = Mutex.new
          end

          def get_raw(url, headers = {}, &)
            session, lock = checkout(URI(url))
            lock.synchronize { session.get_raw(url, headers, &) }
          end

          def close
            @mutex.synchronize do
              @sessions.each_value(&:close)
              @sessions.clear
              @locks.clear
            end
          end

          private

          def checkout(uri)
            origin = uri.origin
            @mutex.synchronize do
              @sessions[origin] = @sessions.delete(origin) || new_session
              [@sessions[origin], @locks[origin] ||= Mutex.new]
            end
          end

          def new_session
            evict_oldest if @sessions.size >= @limit
            Session.new(max_retries: @max_retries)
          end

          def evict_oldest
            origin, session = @sessions.shift
            @locks.delete(origin)
            session.close
          end
        end

        def self.get(url, headers = {})
          JSON.parse(get_raw(url, headers).body)
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
