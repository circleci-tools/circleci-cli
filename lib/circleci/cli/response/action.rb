# frozen_string_literal: true

require 'circleci/cli/response/log_records'

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

        def identity
          [index, step]
        end

        def log_available?
          output_url = @hash['output_url']
          !output_url.nil? && !output_url.empty?
        end

        def log
          return unless log_available?

          each_log_chunk.with_object(+'') { |chunk, log| log << chunk }
        end

        def each_log_chunk
          return enum_for(__method__) unless block_given?

          return unless log_available?

          first = true
          read_log_records do |record|
            yield "\n" unless first
            yield record.fetch('message').gsub("\r\n", "\n").gsub("\e[A\r\e[2K", '')
            first = false
          end
        end

        def failed?
          @status == 'timedout' || @status == 'failed'
        end

        private

        def read_log_records(&read_record)
          records = LogRecords.new
          Networking::HTTPClient.get_raw(@hash['output_url']) do |response|
            unless response.is_a?(Net::HTTPSuccess)
              raise Thor::Error, "Action log download failed (HTTP #{response.code})"
            end

            response.ignore_eof = false
            response.read_body { |chunk| records.read(chunk, &read_record) }
          end
          records.finish
        end
      end
    end
  end
end
