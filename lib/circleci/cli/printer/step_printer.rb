# frozen_string_literal: true

module CircleCI
  module CLI
    module Printer
      class StepPrinter
        def initialize(steps, pretty: true)
          @steps = steps
          @pretty = pretty
        end

        def to_s # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
          if @pretty
            Terminal::Table.new do |t|
              @steps
                .group_by(&:type)
                .each do |key, steps|
                t << :separator
                t << [{ value: Printer.colorize_green(Printer.escape_controls(key)), alignment: :center, colspan: 2 }]
                steps.each { |s| print_actions(t, s) }
              end
            end.to_s
          else
            @steps.group_by(&:type).map do |_, steps|
              steps.flat_map do |step|
                step.actions.map do |a|
                  log = escaped_log(a)&.delete_suffix("\n")
                  "#{action_name(a)}\n#{"#{log}\n" if log}"
                end
              end.join
            end.join("\n")
          end
        end

        private

        def action_name(action)
          name = Printer.escape_controls(action.name.slice(0..120))
          Printer.colorize_by_status(name, action.status)
        end

        def escaped_log(action)
          Printer.escape_controls(action.log, multiline: true) if action.failed?
        end

        def format_time(time)
          return '' unless time

          minute = format('%<time>02d', time: time / 1000 / 60)
          second = format('%<time>02d', time: (time / 1000) % 60)
          "#{minute}:#{second}"
        end

        def print_actions(table, step)
          table << :separator
          step.actions.each do |a|
            table << [
              action_name(a),
              format_time(a.run_time_millis)
            ]
            log = escaped_log(a)
            table << [{ value: wrap_log(log), alignment: :left, colspan: 2 }] if log
          end
        end

        def wrap_log(log)
          log.gsub(/[^\n]{120}(?=[^\n])/) { |chunk| "#{chunk}\n" }
        end
      end
    end
  end
end
