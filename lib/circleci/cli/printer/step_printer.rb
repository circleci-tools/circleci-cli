# frozen_string_literal: true

require 'stringio'
require 'tempfile'
require 'circleci/cli/printer/step_table'

module CircleCI
  module CLI
    module Printer
      class StepPrinter
        def initialize(steps, pretty: true, verbose: false, log_reader: nil)
          @groups = steps.map(&:actions).reject(&:empty?).group_by { |actions| actions.first.type }
          @pretty = pretty
          @verbose = verbose
          @log_reader = log_reader || ->(action, &block) { action.each_log_chunk(&block) }
        end

        def write_to(output)
          if @pretty
            Tempfile.create('circleci-build', encoding: Encoding::UTF_8) do |file|
              write_pretty(output, StepTable.new(file))
            end
          else
            write_compact(output)
          end
        end

        def to_s
          output = StringIO.new
          write_to(output)
          return output.string.delete_suffix("\n") if @pretty || @groups.empty?

          output.string
        end

        private

        def action_name(action)
          name = Printer.escape_controls(action.name.slice(0..120))
          Printer.colorize_by_status(name, action.status)
        end

        def write_compact(output)
          @groups.each_value.with_index do |action_lists, index|
            output.puts unless index.zero?
            action_lists.each { |actions| actions.each { |action| write_action(output, action) } }
          end
          output.puts if @groups.empty?
        end

        def write_action(output, action)
          output.puts(action_name(action))
          output.flush
          return unless show_log?(action)

          ends_with_newline = false
          each_escaped_chunk(action) do |chunk|
            output.write(chunk)
            ends_with_newline = chunk.end_with?("\n")
          end
          output.puts unless ends_with_newline
          output.flush
        end

        def write_pretty(output, table)
          @groups.each do |type, action_lists|
            table.add_header(Printer.colorize_green(Printer.escape_controls(type)))
            action_lists.each do |actions|
              table.add_separator
              actions.each { |action| add_action(table, action) }
            end
          end
          table.write_to(output)
        end

        def add_action(table, action)
          table.add_action(action_name(action), Printer.format_duration(action.run_time_millis))
          table.add_log(enum_for(:each_wrapped_line, action)) if show_log?(action)
        end

        def show_log?(action)
          (@verbose || action.failed?) && action.log_available?
        end

        def each_wrapped_line(action, &write_line)
          tail = ''
          each_escaped_chunk(action) do |chunk|
            tail = wrap_chunk(tail + chunk, &write_line)
            next unless tail.end_with?("\n")

            write_line.call(tail.delete_suffix("\n"))
            tail = ''
          end
          write_line.call(tail) unless tail.empty?
        end

        def wrap_chunk(text)
          last = ''
          text.scan(/[^\n]{1,120}\n?|\n/) do |segment|
            yield last.delete_suffix("\n") unless last.empty?
            last = segment
          end
          last
        end

        def each_escaped_chunk(action)
          suffix = ''
          @log_reader.call(action) do |chunk|
            next if chunk.empty?

            text = suffix + chunk
            suffix = text.end_with?("\r") ? "\r" : ''
            escaped = Printer.escape_controls(text.delete_suffix(suffix), multiline: true)
            yield escaped unless escaped.empty?
          end
          yield Printer.escape_controls(suffix) unless suffix.empty?
        end
      end
    end
  end
end
