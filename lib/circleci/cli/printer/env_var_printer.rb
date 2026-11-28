# frozen_string_literal: true

module CircleCI
  module CLI
    module Printer
      class EnvVarPrinter
        def initialize(env_vars, project_name, pretty: true)
          @env_vars = env_vars
          @project_name = project_name
          @pretty = pretty
        end

        def to_s
          @pretty ? print_pretty : print_compact
        end

        private

        def print_compact
          rows.map { |name, value| "#{name}=#{value}" }.join("\n")
        end

        def print_pretty
          Terminal::Table.new(title:, headings:, rows:).to_s
        end

        def title
          Printer.colorize_green("Environment Variables / #{Printer.escape_controls(@project_name)}")
        end

        def headings
          %w[Name Value]
        end

        def rows
          @env_vars.map { |env_var| [Printer.escape_controls(env_var.name), Printer.escape_controls(env_var.value)] }
        end
      end
    end
  end
end
