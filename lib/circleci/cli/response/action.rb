# frozen_string_literal: true

module CircleCI
  module CLI
    module Response
      class Action
        attr_reader :name, :status, :index, :step, :end_time, :run_time_millis

        def initialize(hash)
          @hash = hash
          @name = hash['name']
          @status = hash['status']
          @index = hash['index']
          @step = hash['step']
          @end_time = hash['end_time']
          @run_time_millis = hash['run_time_millis']
        end

        def log
          output_url = @hash['output_url']
          return if output_url.nil? || output_url.empty?

          log_records(output_url).map do |result|
            result['message'].gsub("\r\n", "\n").gsub("\e[A\r\e[2K", '')
          end.join("\n")
        end

        def failed?
          @status == 'timedout' || @status == 'failed'
        end

        private

        def log_records(output_url)
          response = Networking::HTTPClient.get_raw(output_url)
          return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

          raise Thor::Error, "Action log download failed (HTTP #{response.code})"
        end
      end
    end
  end
end
