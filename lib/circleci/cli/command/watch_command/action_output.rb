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

        def initialize(url, session)
          @url = url
          @session = session
          @read_byte = 0
          @line_tail = ''.b
        end

        def read(&write)
          headers = { 'Range' => "bytes=#{@read_byte}-" }
          complete = false
          @session.get_raw(@url, headers) { |response| complete = read_output(response, &write) }
          complete
        rescue *OUTPUT_READ_ERRORS
          false
        end

        def finish_output?(final: true, &)
          attempts = final ? 2 : 1
          complete = attempts.times.any? { read(&) }

          flush_output(&) if complete || final
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
          end
          successful || response.is_a?(Net::HTTPRangeNotSatisfiable)
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
