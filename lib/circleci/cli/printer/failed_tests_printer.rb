# frozen_string_literal: true

module CircleCI
  module CLI
    module Printer
      module FailedTestsPrinter
        class << self
          def render(job_name, failures:, records_received:)
            heading = "  #{Printer.escape_controls(job_name)}"
            return "#{heading}\n    No uploaded test results." unless records_received

            return "#{heading}\n    No failures in uploaded test results." if failures.empty?

            [heading, *failures.map { |test| format_failure(test) }].join("\n")
          end

          private

          def format_failure(test)
            name, file = test.values_at('name', 'file').map { |value| Printer.escape_controls(value) }
            location = " (#{file})" unless file.to_s.empty?
            message = Printer.escape_controls(test['message'].to_s, multiline: true)
            ["    - #{name}#{location}", *message.lines(chomp: true).map { |line| "      #{line}" }].join("\n")
          end
        end
      end
    end
  end
end
