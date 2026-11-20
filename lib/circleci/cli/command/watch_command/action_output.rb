# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class ActionOutput
        OUTPUT_READ_ERRORS = [
          EOFError, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Errno::ECONNRESET,
          Errno::ECONNABORTED, Errno::EPIPE, Errno::ETIMEDOUT, Errno::ECONNREFUSED
        ].freeze
        OUTPUT_SUFFIX = /(?:\r|[\xC2-\xDF]|[\xE0-\xEF][\x80-\xBF]?|[\xF0-\xF4][\x80-\xBF]{0,2})\z/n

        def initialize(url)
          @url = url
          @read_byte = 0
          @output_suffix = ''.b
          @needs_newline = false
        end

        def read(&write)
          headers = { 'Range' => "bytes=#{@read_byte}-" }
          complete = false
          Networking::HTTPClient.get_raw(@url, headers) { |response| complete = read_output(response, &write) }
          complete
        rescue *OUTPUT_READ_ERRORS
          false
        end

        def finish_output?(&)
          complete = 2.times.any? { read(&) }

          flush_output(&)
          complete
        end

        private

        def output_response?(response)
          response.is_a?(Net::HTTPPartialContent) || (@read_byte.zero? && response.is_a?(Net::HTTPSuccess))
        end

        def read_output(response, &write)
          successful = output_response?(response)
          response.ignore_eof = false
          response.read_body do |chunk|
            next if !successful || chunk.empty?

            stream_output(chunk.b, &write)
            @read_byte += chunk.bytesize
            @needs_newline = !chunk.end_with?("\n")
          end
          successful || response.is_a?(Net::HTTPRangeNotSatisfiable)
        end

        def stream_output(chunk, &)
          # Retain a partial UTF-8 character or CRLF across chunks and polls.
          text = @output_suffix + chunk
          @output_suffix = text.slice!(OUTPUT_SUFFIX) || ''.b
          write_escaped_output(text, &)
        end

        def flush_output(&write)
          write_escaped_output(@output_suffix, &write)
          write.call("\n") if @needs_newline
          @output_suffix = ''.b
          @needs_newline = false
        end

        def write_escaped_output(text)
          yield Printer.escape_controls(text, multiline: true) unless text.empty?
        end
      end
    end
  end
end
