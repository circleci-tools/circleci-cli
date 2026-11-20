# frozen_string_literal: true

module CircleCI
  module CLI
    module Printer
      class StepTable
        def initialize(file)
          @file = file
          @rows = []
          @logs = {}
        end

        def add_header(name)
          add_separator
          @rows << [{ value: name, alignment: :center, colspan: 2 }]
        end

        def add_separator
          @rows << :separator
        end

        def add_action(name, duration)
          @rows << [name, duration]
        end

        def add_log(lines)
          width, count, end_position = spool_log(lines)
          @file.truncate(end_position)
          @file.seek(end_position)
          @logs[@rows.size] = count if count.positive?
          @rows << [{ value: ' ' * width, colspan: 2 }]
        end

        def write_to(output)
          @file.rewind
          table = Terminal::Table.new(rows: @rows)
          # The rendered template has one line per row, including the log placeholders.
          table.to_s.split("\n", -1).each_with_index do |line, index|
            count = @logs[index - 1]
            if count
              count.times { write_log_line(output, line.length - 4) }
            else
              output.puts(line)
            end
          end
        end

        private

        def spool_log(lines)
          width = count = 0
          end_position = @file.pos
          lines.each_with_index do |line, index|
            @file.puts(line)
            next if line.empty?

            width = [width, Unicode::DisplayWidth.of(line)].max
            count = index + 1
            end_position = @file.pos
          end
          [count.positive? ? [width, 1].max : width, count, end_position]
        end

        def write_log_line(output, width)
          line = @file.readline.delete_suffix("\n")
          padding = ' ' * (width - Unicode::DisplayWidth.of(line))
          output.puts("| #{line}#{padding} |")
        end
      end
    end
  end
end
