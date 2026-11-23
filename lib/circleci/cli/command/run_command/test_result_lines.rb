# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class TestResultLines
        MAX_RECORD_BYTES = 256 * 1024

        def self.each(response)
          response.ignore_eof = false
          pending = String.new(encoding: Encoding::BINARY)
          each_part(response) do |part|
            complete = part.end_with?("\n")
            pending = append(pending, part, complete)
            next unless complete

            yield pending
            pending = String.new(encoding: Encoding::BINARY)
          end
          yield pending if pending.nil? || !pending.empty?
        end

        def self.each_part(response, &)
          response.read_body { |chunk| chunk.each_line("\n", &) }
        end
        private_class_method :each_part

        def self.append(pending, part, complete)
          bytes = part.bytesize - (complete ? 1 : 0)
          return unless pending && pending.bytesize + bytes <= MAX_RECORD_BYTES

          pending << part.byteslice(0, bytes).b
        end
        private_class_method :append
      end
    end
  end
end
