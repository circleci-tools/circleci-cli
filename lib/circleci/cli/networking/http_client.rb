# frozen_string_literal: true

require 'net/http'
require 'json'

module CircleCI
  module CLI
    module Networking
      module HTTPClient
        def self.get(url, headers = {})
          JSON.parse(get_raw(url, headers).body)
        end

        def self.get_raw(url, headers = {})
          uri = URI(url)
          req = Net::HTTP::Get.new(uri)
          headers.each { |key, value| req[key] = value }
          Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.request(req)
          end
        end

        def self.post_form(url, params = {})
          uri = URI(url)
          res = Net::HTTP.post_form(uri, params)
          JSON.parse(res.body)
        end
      end
    end
  end
end
