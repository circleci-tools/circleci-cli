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

          Networking::HTTPClient.get(output_url).map { |entry| format_message(entry['message']) }.join("\n")
        end

        def failed?
          @status == 'timedout' || @status == 'failed'
        end

        private

        def format_message(message)
          message.gsub("\r\n", "\n")
                 .gsub("\e[A\r\e[2K", '')
                 .scan(/.{1,120}/)
                 .join("\n")
        end
      end
    end
  end
end
