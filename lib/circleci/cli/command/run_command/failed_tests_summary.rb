# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class FailedTestsSummary
        def initialize(&fetch_results)
          @fetch_results = fetch_results
        end

        def render(groups)
          sections = groups.filter_map do |name, jobs|
            failed_jobs = jobs.select { |job| job.fetch('attributes')['outcome'] == 'failed' }
            next if failed_jobs.empty?

            [Printer.escape_controls(name), *failed_jobs.map { |job| failed_job_summary(job) }].join("\n")
          end
          sections << 'No failed jobs found.' if sections.empty?
          ['Failed tests', *sections].join("\n\n")
        end

        private

        def failed_job_summary(job)
          name = job.fetch('attributes').fetch('name')
          job_id = job.fetch('id')
          Printer::FailedTestsPrinter.render(name, **test_results(job_id))
        rescue Thor::Error => e
          name = Printer.escape_controls(name)
          detail = Printer.escape_controls(e.message)
          raise Thor::Error, "Unable to load test results for job #{name} (#{job_id}): #{detail}"
        end

        def test_results(job_id)
          failures = []
          records_received = false
          each_test_line(job_id) do |line|
            record = parse_record(line)
            next unless record

            records_received = true
            failures << record if record['result'] == 'failure'
          end
          { failures:, records_received: }
        end

        def each_test_line(job_id)
          pending = String.new(encoding: Encoding::BINARY)
          read_chunks(job_id) do |chunk|
            chunk.b.each_line("\n") do |part|
              pending << part
              next unless part.end_with?("\n")

              yield pending
              pending.clear
            end
          end
          yield pending unless pending.empty?
        end

        def read_chunks(job_id, &read_chunk)
          @fetch_results.call(job_id) do |response|
            response.read_body(&read_chunk) if response.is_a?(Net::HTTPSuccess)
          end
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
