# frozen_string_literal: true

require 'circleci/cli/command/watch_command/action_output'
require 'circleci/cli/command/watch_command/step_log'

module CircleCI
  module CLI
    module Command
      class ActionLogTracker # rubocop:disable Metrics/ClassLength
        INCOMPLETE_OUTPUT_WARNING = 'Warning: Step log output may be incomplete.'

        attr_reader :messages

        def initialize(build, verbose:, log_sessions:, messages:, output:)
          @build = build
          @verbose = verbose
          @log_sessions = log_sessions
          @messages = messages
          @output = output
          @output_lock = Mutex.new
          @retained_log_bytes = 0
          @action_outputs = {}
          @completed_outputs = {}
        end

        def close
          @messages.each_value(&:close)
          @messages.clear
          @retained_log_bytes = 0
        end

        def clear_actions
          @action_outputs.clear
        end

        def refresh_action_outputs(actions, continuing:, stopping: false)
          track_actions(actions.reject(&:skipped?))
          running = continuing ? actions.select(&:running?).map(&:identity) : []
          finish_outputs(running, stopping:)
        end

        def finish_action_logs(step)
          return if @messages.empty?

          running = step.status == 'running'
          step.actions.each do |action|
            next if action.end_time.nil? || (running && action.failed?)

            finish_action_log(action)
          end
        end

        def print_completed_outputs(step, stopping:)
          completed_log_actions(step).each do |action|
            identity = action.identity
            next if identity.include?(nil) || @action_outputs.key?(identity)

            output = @completed_outputs.fetch(identity) { @completed_outputs[identity] = new_output(identity) }
            next unless output

            read_completed_output(output, identity, stopping:)
          end
        end

        def update_actions
          actions = @action_outputs.compact
          return if actions.empty?
          return read_action(*actions.first, @log_sessions.first) if actions.one?

          read_actions_concurrently(actions)
        end

        def retain_output(identity, chunk)
          log = (@messages[identity] ||= StepLog.new)
          remaining = StepLog::RETENTION_LIMIT - @retained_log_bytes
          @retained_log_bytes += log.append(chunk, remaining:)
        end

        private

        def track_actions(actions)
          actions.each do |action|
            next if action.identity.include?(nil) || (action.end_time && !show_action_log?(action))

            @action_outputs.fetch(action.identity) do |identity|
              @action_outputs[identity] = @completed_outputs.fetch(identity) { new_output(identity) }
            end
          end
        end

        def new_output(identity)
          project = [@build.username, @build.reponame, @build.build_number].join('/')
          url = "https://circleci.com/api/private/output/raw/github/#{project}/output/#{identity.join('/')}"
          ActionOutput.new(url, @log_sessions.first)
        end

        def show_action_log?(action)
          @verbose || action.failed?
        end

        def completed_log_actions(step)
          step.actions.select { |action| action.end_time && show_action_log?(action) }
        end

        def finish_action_log(action)
          log = @messages.delete(action.identity)
          return unless log

          log.write_to($stdout) if action.failed?
        ensure
          if log
            log.close
            @retained_log_bytes -= log.bytesize
          end
        end

        def read_completed_output(output, identity, stopping:)
          complete = output.finish_output?(final: stopping) { |chunk| @output.call(chunk) }
          @completed_outputs[identity] = nil if complete || stopping
          warn INCOMPLETE_OUTPUT_WARNING if stopping && !complete
        end

        def finish_outputs(running, stopping: false)
          failed = @action_outputs.except(*running).filter_map do |identity, output|
            next unless output

            complete = output.finish_output? { |chunk| write_output(identity, chunk) }
            resolve_finished_output(identity, output, complete:, stopping:)
            identity unless complete
          end
          warn INCOMPLETE_OUTPUT_WARNING if stopping && failed.any?
        end

        def resolve_finished_output(identity, output, complete:, stopping:)
          if complete || stopping
            @action_outputs[identity] = nil
            @completed_outputs[identity] = nil
          else
            # Keep the reader so the next refresh or shutdown can resume from its byte offset.
            @action_outputs.delete(identity)
            @completed_outputs[identity] = output
          end
        end

        def read_actions_concurrently(actions)
          workers = []
          pending = Queue.new
          actions.each { |entry| pending << entry }
          pending.close
          start_log_workers(workers, pending, actions.size)
          workers.each(&:value)
        ensure
          stop_log_workers(workers)
        end

        def start_log_workers(workers, pending, count)
          Thread.handle_interrupt(Object => :never) do
            @log_sessions.take(count).each do |session|
              workers << Thread.new { read_pending_actions(pending, session) }
            end
          end
        end

        def stop_log_workers(workers)
          workers.each(&:kill)
          workers.each { |worker| worker.join if worker.alive? }
        end

        def read_pending_actions(pending, session)
          while (entry = pending.pop)
            read_action(*entry, session)
          end
        end

        def read_action(identity, output, session)
          output.read(session:) { |chunk| write_output(identity, chunk) }
        end

        def write_output(identity, chunk)
          @output_lock.synchronize do
            if @verbose
              @output.call(chunk)
            else
              # Defer thread termination until any spill file is registered for cleanup.
              Thread.handle_interrupt(Object => :never) do
                retain_output(identity, chunk)
              end
            end
          end
        end
      end
    end
  end
end
