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

        # Each origin has one session and a request mutex. The pool mutex protects the LRU
        # order and counts both active and queued callers before they take the request mutex.
        class SessionPool
          LIMIT = 4
          Entry = Struct.new(:session, :lock, :callers)
          private_constant :Entry

          def self.open(max_retries: 0, limit: LIMIT)
            pool = new(max_retries:, limit:)
            yield pool
          ensure
            pool&.close
          end

          def initialize(max_retries: 0, limit: LIMIT)
            raise ArgumentError, 'Session pool limit must be positive' unless limit.positive?

            @max_retries = max_retries
            @limit = limit
            @sessions = {}
            @mutex = Mutex.new
            @available = ConditionVariable.new
          end

          def get_raw(url, headers = {}, &)
            entry = checkout(URI(url).origin)
            entry.lock.synchronize { entry.session.get_raw(url, headers, &) }
          ensure
            checkin(entry) if entry
          end

          def close
            @mutex.synchronize do
              @sessions.each_value { |entry| entry.session.close }
              @sessions.clear
            end
          end

          private

          def checkout(origin)
            @mutex.synchronize do
              @available.wait(@mutex) until @sessions.key?(origin) || make_room?
              entry = @sessions.delete(origin) || Entry.new(Session.new(max_retries: @max_retries), Mutex.new, 0)
              entry.callers += 1
              @sessions[origin] = entry
            end
          end

          def checkin(entry)
            @mutex.synchronize do
              entry.callers -= 1
              @available.broadcast if entry.callers.zero?
            end
          end

          def make_room?
            return true if @sessions.size < @limit

            origin, = @sessions.find { |_origin, entry| entry.callers.zero? }
            return false unless origin

            @sessions.delete(origin).session.close
            true
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
