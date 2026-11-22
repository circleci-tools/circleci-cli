# frozen_string_literal: true

require 'circleci/cli/command/run_command/run_request_pool'

module CircleCI
  module CLI
    module Command
      class FailedTestsSummary
        def initialize(&fetch_results)
          @fetch_results = fetch_results
        end

        def render(groups)
          failed_groups = failed_job_groups(groups)
          summaries = RunRequestPool.fetch(failed_groups.flat_map(&:last), &method(:failed_job_summary))
          sections = failed_groups.map do |name, jobs|
            [Printer.escape_controls(name), *summaries.shift(jobs.size)].join("\n")
          end
          sections << 'No failed jobs found.' if sections.empty?
          ['Failed tests', *sections].join("\n\n")
        end

        private

        def failed_job_groups(groups)
          groups.filter_map do |name, jobs|
            failed_jobs = jobs.select { |job| job.fetch('attributes')['outcome'] == 'failed' }
            [name, failed_jobs] unless failed_jobs.empty?
          end
        end

        def failed_job_summary(session, job)
          name = job.fetch('attributes').fetch('name')
          job_id = job.fetch('id')
          Printer::FailedTestsPrinter.render(name, **test_results(session, job_id))
        rescue Thor::Error => e
          name = Printer.escape_controls(name)
          detail = Printer.escape_controls(e.message)
          raise Thor::Error, "Unable to load test results for job #{name} (#{job_id}): #{detail}"
        end

        def test_results(session, job_id)
          results = nil
          @fetch_results.call(session, job_id) do |response|
            results = collect_results(response) if response.is_a?(Net::HTTPSuccess)
          end
          results
        end

        def collect_results(response)
          response.ignore_eof = false
          failures = []
          records_received = false
          each_test_line(response) do |line|
            record = parse_record(line)
            next unless record

            records_received = true
            failures << record if record['result'] == 'failure'
          end
          { failures:, records_received: }
        end

        def each_test_line(response)
          pending = String.new(encoding: Encoding::BINARY)
          response.read_body do |chunk|
            chunk.b.each_line("\n") do |part|
              pending << part
              next unless part.end_with?("\n")

              yield pending
              pending.clear
            end
          end
          yield pending unless pending.empty?
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
