# frozen_string_literal: true

require 'stringio'
require 'tempfile'

module CircleCI
  module CLI
    module Command
      class StepLog
        MEMORY_LIMIT = 256 * 1024
        RETENTION_LIMIT = 16 * 1024 * 1024

        attr_reader :bytesize

        def initialize
          @memory = StringIO.new(''.b)
          @bytesize = 0
          @truncated = false
        end

        def append(chunk, remaining: RETENTION_LIMIT - @bytesize)
          return 0 if @truncated

          if chunk.bytesize > remaining
            @truncated = true
            chunk = chunk.byteslice(0, remaining).scrub('')
          end
          spill if @memory && @memory.size + chunk.bytesize > MEMORY_LIMIT
          written = (@file || @memory).write(chunk)
          @bytesize += written
          written
        end

        def write_to(output)
          source = @file || @memory
          source.rewind
          IO.copy_stream(source, output)
          output.write("\n[Step log truncated: retention limit reached.]\n") if @truncated
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
