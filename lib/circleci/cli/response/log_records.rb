# frozen_string_literal: true

module CircleCI
  module CLI
    module Response
      class LogRecords
        TOKENS = /["\\{}\[\],]|[^"\\{}\[\],]+/
        WHITESPACE = /\A[ \t\r\n]*\z/

        def initialize
          @state = :array_start
          @depth = 0
        end

        def read(chunk)
          chunk.b.scan(TOKENS) do |token|
            if @record
              record = read_record(token)
              yield record if record
            else
              read_array(token)
            end
          end
        end

        def finish
          invalid_json unless @state == :array_end
        end

        private

        def read_array(token)
          return if WHITESPACE.match?(token)

          case [@state, token]
          when [:array_start, '['] then @state = :first_record
          when [:first_record, ']'], [:separator, ']'] then @state = :array_end
          when [:separator, ','] then @state = :next_record
          when [:first_record, '{'], [:next_record, '{'] then start_record
          else invalid_json
          end
        end

        def start_record
          @record = +'{'.b
          @depth = 1
          @state = :record
        end

        def read_record(token)
          @record << token
          advance_record(token)
          return unless @depth.zero?

          record = JSON.parse(@record)
          @record = nil
          @state = :separator
          record
        end

        def advance_record(token)
          if @escaped
            @escaped = false
          elsif @quoted
            @escaped = token == '\\'
            @quoted = false if token == '"'
          else
            advance_structure(token)
          end
        end

        def advance_structure(token)
          case token
          when '"' then @quoted = true
          when '{', '[' then @depth += 1
          when '}', ']' then @depth -= 1
          end
        end

        def invalid_json
          raise JSON::ParserError, 'Invalid action log JSON array'
        end
      end
    end
  end
end
