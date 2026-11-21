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
        CONTENT_RANGE = %r{\Abytes (\d+)-(\d+)/(\d+|\*)\z}i

        def initialize(url, session)
          @url = url
          @session = session
          @read_byte = 0
          reset_output_tail
        end

        def read(&)
          headers = { 'Range' => "bytes=#{@read_byte}-" }
          status = :retry
          @session.get_raw(@url, headers) { |response| status = read_output(response, &) }
          status
        rescue *OUTPUT_READ_ERRORS
          :retry
        end

        def finish_output?(final: true, &)
          complete = final ? drain_output?(&) : read(&) == :complete
          flush_output(&) if complete || final
          complete
        end

        private

        def drain_output?(&)
          2.times.any? do
            status = read(&)
            status = read(&) while status == :more
            status == :complete
          end
        end

        def output_response?(response)
          response.is_a?(Net::HTTPPartialContent) || (@read_byte.zero? && response.is_a?(Net::HTTPSuccess))
        end

        def read_output(response, &)
          content_range = response['Content-Range'] if response.is_a?(Net::HTTPPartialContent)
          return read_range(response, content_range, &) if content_range

          successful = output_response?(response)
          read_body(response, successful, &)
          return :retry unless successful || response.is_a?(Net::HTTPRangeNotSatisfiable)

          @output_length && @read_byte < @output_length ? :retry : :complete
        end

        def read_range(response, content_range, &)
          range_end = parse_range_end(content_range)
          read_body(response, range_end, &)
          return :retry unless @read_byte == range_end

          @read_byte == @output_length ? :complete : :more
        end

        def parse_range_end(content_range)
          range = CONTENT_RANGE.match(content_range)
          return unless range

          first, last, length = range.captures.map { |value| Integer(value, 10, exception: false) }
          return unless first == @read_byte && (first...length).cover?(last)

          @output_length = length if length
          last + 1
        end

        def read_body(response, successful, &)
          response.ignore_eof = false
          response.read_body do |chunk|
            next if !successful || chunk.empty?

            stream_output(chunk.b, &)
            @read_byte += chunk.bytesize
            @needs_newline = !chunk.end_with?("\n")
          end
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
          reset_output_tail
        end

        def reset_output_tail
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
