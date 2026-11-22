# frozen_string_literal: true

require 'circleci/cli/command/run_lookup'
require 'circleci/cli/command/run_command/failed_tests_summary'

module CircleCI
  module CLI
    module Command
      class RunCommand < RunLookup
        def self.run(run_id, failed_tests: false)
          raise Thor::Error, 'Run ID must be a UUID.' unless UUID.match?(run_id)

          new(setup_token).summary(run_id, failed_tests:)
        end

        def summary(run_id, failed_tests: false)
          title, workflow_list = Networking::HTTPClient::Session.open(max_retries: 1) do |session|
            [run_title(session, run_id), workflows(session, run_id)]
          end
          groups = fetch_workflow_jobs(workflow_list)
          table = Terminal::Table.new(title:, headings: ['Workflow', 'Job', 'Status', 'Job Number'],
                                      rows: summary_rows(groups)).to_s
          return table unless failed_tests

          tests = FailedTestsSummary.new { |session, job_id| request("jobs/#{job_id}/tests", client: session) }
          [table, tests.render(groups)].join("\n\n")
        end

        private

        def run_title(session, run_id)
          run = get(session, "runs/#{run_id}").fetch('data').fetch('attributes')
          status = run['current_outcome'] || run.fetch('phase')
          Printer.escape_controls("Run ##{run.fetch('number')} (#{status})")
        end

        def summary_rows(groups)
          rows = groups.flat_map { |name, jobs| workflow_rows(name, jobs) }
          return [['No workflows found', '-', '-', '-']] if rows.empty?

          rows.map { |row| row.map { |cell| Printer.escape_controls(cell) } }
        end

        def workflow_rows(name, jobs)
          return [[name, 'No jobs found', '-', '-']] if jobs.empty?

          jobs.map { |job| job_row(name, job.fetch('attributes')) }
        end

        def job_row(workflow_name, job)
          status = job['outcome'] || job.fetch('phase')
          status = "#{status} (approval)" if job['type'] == 'approval'
          [workflow_name, job.fetch('name'), status, job['number'] || '-']
        end
      end
    end
  end
end
