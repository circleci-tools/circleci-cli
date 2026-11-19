# frozen_string_literal: true

require 'circleci/cli/printer/project_printer'
require 'circleci/cli/printer/build_printer'
require 'circleci/cli/printer/step_printer'

module CircleCI
  module CLI
    module Printer
      class << self
        def colorize_red(string)
          colorize(string, '0;31;49')
        end

        def colorize_green(string)
          colorize(string, '0;32;49')
        end

        def colorize_yellow(string)
          colorize(string, '0;33;49')
        end

        def colorize_light_black(string)
          colorize(string, '0;90;49')
        end

        def escape_controls(value, multiline: false)
          return value unless value.is_a?(String)

          text = value.encoding == Encoding::BINARY ? decode_binary_text(value) : value
          text = text.gsub("\r\n", "\n") if multiline
          controls = multiline ? /[[:cntrl:]&&[^\n]]/ : /[[:cntrl:]]/
          text.gsub(controls) { |character| format('\\x%02X', character.ord) }
        end

        def colorize_by_status(string, status)
          case status
          when 'success', 'fixed' then colorize_green(string)
          when 'canceled' then colorize_yellow(string)
          when 'failed', 'timedout', 'infrastructure_fail' then colorize_red(string)
          when 'no_tests', 'not_run' then colorize_light_black(string)
          else string
          end
        end

        private

        def decode_binary_text(value)
          value.dup.force_encoding(Encoding::UTF_8).scrub do |invalid_bytes|
            invalid_bytes.bytes.map { |byte| format('\\x%02X', byte) }.join
          end
        end

        def colorize(string, color_code)
          "\e[#{color_code}m#{string}\e[0m"
        end
      end
    end
  end
end
