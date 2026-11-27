# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class StepNotifier
        def initialize(verbose:, puts:, bordered:)
          @verbose = verbose
          @puts = puts
          @bordered = bordered
          @lock = Mutex.new
          @last_printed_step = nil
          @step_line_rewrites_disabled = false
        end

        def disable_step_line_rewrites
          @lock.synchronize { @step_line_rewrites_disabled = true }
        end

        def notify_step_change(step, previous_status)
          return on_new_step(step) unless previous_status

          on_new_step_status(step) unless previous_status == step.status
        end

        def on_new_step(step)
          name = Printer.escape_controls(step.name)
          return @bordered.call(name) if @verbose

          status = step.status
          return print_running_step(step, name) if status == 'running'

          print_step_status(step, Printer.colorize_by_status(name, status), eligible_for_rewrite: false)
        end

        def on_new_step_status(step)
          return if @verbose

          status = step.status
          return if status == 'running'

          name = Printer.escape_controls(step.name)
          print_step_status(step, Printer.colorize_by_status(name, status), eligible_for_rewrite: true)
        end

        private

        def print_running_step(step, name)
          @lock.synchronize do
            @puts.call(name)
            @last_printed_step = step.identity
          end
        end

        # Rewriting the previous line is only safe when that line still belongs to this step: once
        # another step's line has been printed in between, rewrite in place would erase it, so the
        # status update is appended as a new line instead.
        def print_step_status(step, text, eligible_for_rewrite:)
          @lock.synchronize do
            rewrite = eligible_for_rewrite && (@last_printed_step.nil? || @last_printed_step == step.identity)
            prefix = rewrite ? "\e[1A\e[2K\r" : "\e[2K\r"
            @puts.call(@step_line_rewrites_disabled ? text : "#{prefix}#{text}")
            @last_printed_step = step.identity
          end
        end
      end
    end
  end
end
