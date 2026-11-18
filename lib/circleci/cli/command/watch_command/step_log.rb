# frozen_string_literal: true

require 'stringio'
require 'tempfile'

module CircleCI
  module CLI
    module Command
      class StepLog
        MEMORY_LIMIT = 256 * 1024

        def initialize
          @memory = StringIO.new(''.b)
        end

        def append(chunk)
          spill if @memory && @memory.size + chunk.bytesize + 1 > MEMORY_LIMIT
          (@file || @memory).puts(chunk)
        end

        def write_to(output)
          source = @file || @memory
          source.rewind
          IO.copy_stream(source, output)
          output.flush
        end

        def close
          @file&.close!
          @memory = nil
        end

        private

        def spill
          @file = Tempfile.new('circleci-watch', binmode: true)
          @memory.rewind
          IO.copy_stream(@memory, @file)
          @memory = nil
        end
      end
    end
  end
end
