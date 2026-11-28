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

          def post_raw(url, headers = {}, &)
            uri = URI(url)
            request = HTTPClient.post_request(uri, headers)
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

        # Checked-out sessions belong to one worker until its response finishes.
        # Idle sessions are kept in return order for reuse or eviction.
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
            raise ArgumentError, 'HTTP session pool limit must be positive' unless limit.positive?

            @limit = limit
            @idle = {}
            @active = 0
            @mutex = Mutex.new
            @available = ConditionVariable.new
          end

          def get_raw(url, headers = {}, &)
            origin = URI(url).origin
            session = checkout(origin)
            session.get_raw(url, headers, &)
          ensure
            checkin(session, origin) if session
          end

          def close
            @mutex.synchronize do
              @closed = true
              @available.broadcast
              @idle.each_key(&:close)
              @idle.clear
            end
          end

          private

          def checkout(origin)
            @mutex.synchronize do
              @available.wait(@mutex) while !@closed && @active >= @limit
              raise IOError, 'HTTP session pool is closed' if @closed

              session = @idle.key(origin) || new_session
              @idle.delete(session)
              @active += 1
              session
            end
          end

          def checkin(session, origin)
            @mutex.synchronize do
              @active -= 1
              @available.signal
              if @closed
                session.close
              else
                @idle[session] = origin
              end
            end
          end

          def new_session
            @idle.shift.first.close if @active + @idle.size >= @limit
            Session.new(max_retries: @max_retries)
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

        def self.post_request(uri, headers)
          Net::HTTP::Post.new(uri).tap do |request|
            headers.each { |key, value| request[key] = value }
          end
        end
      end
    end
  end
end
