# frozen_string_literal: true

require 'circleci/cli/command/run_command/run_request_pool'
require 'circleci/cli/command/run_command/test_result_lines'

module CircleCI
  module CLI
    module Command
      class FailedTestsSummary
        MAX_OUTPUT_BYTES = 1024 * 1024
        TRUNCATION_NOTICE = "\n\nFailed test output truncated. Some uploaded test results were omitted."
        BUDGET_EXHAUSTED = :failed_tests_summary_budget_exhausted

        def initialize(&fetch_results)
          @fetch_results = fetch_results
        end

        def render(groups)
          jobs = failed_jobs(groups)
          return "Failed tests\n\nNo failed jobs found." if jobs.empty?

          output = +'Failed tests'
          truncated = false
          each_job_summary(jobs) do |summary|
            status = append_job_summary(output, summary)
            return output << TRUNCATION_NOTICE if status == :truncated

            truncated ||= status == :oversized
          end
          truncated ? output << TRUNCATION_NOTICE : output
        end

        private

        def append_job_summary(output, summary)
          return :truncated if output.bytesize + TRUNCATION_NOTICE.bytesize == MAX_OUTPUT_BYTES
          raise summary if summary.is_a?(StandardError)

          header, entries, status, capped = summary
          entries = job_entries(entries, status, capped)
          append(output, header) && entries.all? { |entry| append(output, entry) } && !capped ? status : :truncated
        end

        def each_job_summary(jobs, &)
          jobs.each_slice(RunRequestPool::LIMIT) do |batch|
            RunRequestPool.fetch(batch, raise_errors: false, &method(:failed_job_summary)).each(&)
          end
        end

        def failed_jobs(groups)
          groups.flat_map do |name, jobs|
            jobs.select { |job| job.fetch('attributes')['outcome'] == 'failed' }.map.with_index do |job, index|
              [index.zero? ? name : nil, job]
            end
          end
        end

        def append(output, entry)
          return false if output.bytesize + entry.bytesize + TRUNCATION_NOTICE.bytesize > MAX_OUTPUT_BYTES

          output << entry
        end

        def failed_job_summary(session, item)
          workflow, job = item
          name = job.fetch('attributes').fetch('name')
          job_id = job.fetch('id')
          header = workflow ? "\n\n#{Printer.escape_controls(workflow)}\n" : "\n"
          header = "#{header}  #{Printer.escape_controls(name)}"
          [header, *test_results(session, job_id)]
        rescue Thor::Error => e
          name = Printer.escape_controls(name)
          detail = Printer.escape_controls(e.message)
          raise Thor::Error, "Unable to load test results for job #{name} (#{job_id}): #{detail}"
        end

        def test_results(session, job_id)
          results = nil
          exhausted = catch(BUDGET_EXHAUSTED) do
            @fetch_results.call(session, job_id) do |response|
              results = collect_results(response) if response.is_a?(Net::HTTPSuccess)
            end
            nil
          end
          return results unless exhausted

          # The response body was left unread; the connection can't be reused for the next request.
          session.close
          exhausted
        end

        def collect_results(response)
          entries = []
          bytes = 0
          status = each_failure(response) do |record|
            entry = "\n#{Printer::FailedTestsPrinter.format_failure(record)}"
            bytes += entry.bytesize
            entries << entry if bytes <= MAX_OUTPUT_BYTES
            throw BUDGET_EXHAUSTED, [entries, :received, true] if bytes > MAX_OUTPUT_BYTES
          end
          [entries, status, bytes > MAX_OUTPUT_BYTES]
        end

        def each_failure(response)
          status = :empty
          TestResultLines.each(response) do |line|
            status = :oversized unless line
            record = line && parse_record(line)
            next unless record

            status = :received if status == :empty
            yield record if record['result'] == 'failure'
          end
          status
        end

        def job_entries(entries, status, capped)
          return entries unless entries.empty? && status != :oversized && !capped

          [status == :received ? "\n    No failures in uploaded test results." : "\n    No uploaded test results."]
        end

        def parse_record(line)
          return if line.strip.empty?

          record = JSON.parse(line)
          raise JSON::ParserError unless record.is_a?(Hash)

          record
        rescue JSON::ParserError
          raise Thor::Error, 'CircleCI API returned invalid JSON Lines.'
        end
      end
    end
  end
end
