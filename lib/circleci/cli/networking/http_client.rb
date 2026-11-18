# frozen_string_literal: true

require 'net/http'
require 'json'

module CircleCI
  module CLI
    module Networking
      module HTTPClient
        def self.get(url, headers = {})
          JSON.parse(request(url, headers).body)
        end

        def self.get_raw(url, headers = {})
          response = request(url, headers)
          response.body if response.is_a?(Net::HTTPSuccess)
        end

        def self.post_form(url, params = {})
          res = Net::HTTP.post_form(URI(url), params)
          JSON.parse(res.body)
        end

        def self.request(url, headers)
          uri = URI(url)
          req = Net::HTTP::Get.new(uri)
          headers.each { |key, value| req[key] = value }
          Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.request(req)
          end
        end
        private_class_method :request
      end
    end
  end
end
