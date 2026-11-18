# frozen_string_literal: true

module CircleCI
  module CLI
    module Printer
      class StepPrinter
        def initialize(steps, pretty: true, verbose: false)
          @steps = steps
          @pretty = pretty
          @verbose = verbose
        end

        def to_s # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
          if @pretty
            Terminal::Table.new do |t|
              @steps
                .group_by(&:type)
                .each do |key, steps|
                t << :separator
                t << [{ value: Printer.colorize_green(key), alignment: :center, colspan: 2 }]
                steps.each { |s| print_actions(t, s) }
              end
            end.to_s
          else
            @steps.group_by(&:type).map do |_, steps|
              steps.flat_map do |step|
                step.actions.map do |a|
                  log = log_for(a)
                  "#{Printer.colorize_by_status(a.name.slice(0..120), a.status)}\n#{"#{log}\n" if log}"
                end
              end.join
            end.join("\n")
          end
        end

        private

        def log_for(action)
          action.log if @verbose || action.failed?
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
              Printer.colorize_by_status(a.name.slice(0..120), a.status),
              format_time(a.run_time_millis)
            ]
            log = log_for(a)
            table << [{ value: log, alignment: :left, colspan: 2 }] if log
          end
        end
      end
    end
  end
end
