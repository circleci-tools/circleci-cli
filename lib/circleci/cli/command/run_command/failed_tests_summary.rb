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
          Printer::FailedTestsPrinter.render(name, test_results(job_id))
        rescue Thor::Error => e
          name = Printer.escape_controls(name)
          detail = Printer.escape_controls(e.message)
          raise Thor::Error, "Unable to load test results for job #{name} (#{job_id}): #{detail}"
        end

        def test_results(job_id)
          response = @fetch_results.call(job_id)
          response.body.to_s.lines.reject { |line| line.strip.empty? }.map do |line|
            record = JSON.parse(line)
            raise JSON::ParserError unless record.is_a?(Hash)

            record
          end
        rescue JSON::ParserError
          raise Thor::Error, 'CircleCI API returned invalid JSON Lines.'
        end
      end
    end
  end
end
