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
          HTTPClient.get(@hash['output_url'])
                    .map do |r|
            r['message']
              .gsub("\r\n", "\n")
              .gsub("\e[A\r\e[2K", '')
              .scan(/.{1,120}/)
              .join("\n")
          end
            .join("\n")
        end

        def failed?
          @status == 'timedout' || @status == 'failed'
        end
      end
    end
  end
end
