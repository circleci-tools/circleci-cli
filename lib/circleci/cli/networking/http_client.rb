# frozen_string_literal: true

require 'net/http'
require 'json'

module CircleCI
  module CLI
    module Networking
      module HTTPClient
        class Session
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
            @http.max_retries = 0
            @http
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
