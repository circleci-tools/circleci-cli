# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class ActionOutput
        OUTPUT_READ_ERRORS = [
          EOFError, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Errno::ECONNRESET,
          Errno::ECONNABORTED, Errno::EPIPE, Errno::ETIMEDOUT, Errno::ECONNREFUSED
        ].freeze
        LINE_BUFFER_LIMIT = 64 * 1024
        OUTPUT_SUFFIX = /(?:\r|[\xC2-\xDF]|[\xE0-\xEF][\x80-\xBF]?|[\xF0-\xF4][\x80-\xBF]{0,2})\z/n
        CONTENT_RANGE = %r{\Abytes (\d+)-(\d+)/(\d+|\*)\z}i

        def initialize(url, session)
          @url = url
          @session = session
          @read_byte = 0
          @line_tail = ''.b
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
          end
        end

        def stream_output(chunk, &)
          @line_tail << chunk
          last_newline = @line_tail.rindex("\n")
          write_escaped_output(@line_tail.slice!(0, last_newline + 1), &) if last_newline

          flush_long_line(&) while @line_tail.bytesize > LINE_BUFFER_LIMIT
        end

        def flush_long_line(&)
          # Split oversized unfinished lines at a UTF-8 boundary and end each fragment.
          fragment = @line_tail.byteslice(0, LINE_BUFFER_LIMIT)
          fragment.slice!(OUTPUT_SUFFIX)
          @line_tail.slice!(0, fragment.bytesize)
          write_escaped_output(fragment, terminate: true, &)
        end

        def flush_output(&)
          write_escaped_output(@line_tail, terminate: true, &)
          @line_tail.clear
        end

        def write_escaped_output(text, terminate: false)
          return if text.empty?

          escaped = Printer.escape_controls(text, multiline: true)
          escaped << "\n" if terminate
          yield escaped
        end
      end
    end
  end
end
