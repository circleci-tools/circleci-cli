# frozen_string_literal: true

module CircleCI
  module CLI
    module Printer
      module FailedTestsPrinter
        class << self
          def format_failure(test)
            name, file = test.values_at('name', 'file').map { |value| Printer.escape_controls(value) }
            location = " (#{file})" unless file.to_s.empty?
            message = Printer.escape_controls(test['message'].to_s, multiline: true)
            message.each_line(chomp: true).reduce("    - #{name}#{location}") do |entry, line|
              entry << "\n      " << line
            end
          end
        end
      end
    end
  end
end
