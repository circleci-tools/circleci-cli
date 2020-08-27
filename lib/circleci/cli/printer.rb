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

        private

        def colorize(string, color_code)
          "\e[#{color_code}m#{string}\e[0m"
        end
      end
    end
  end
end
