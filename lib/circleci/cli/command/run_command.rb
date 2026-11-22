# frozen_string_literal: true

require 'circleci/cli/command/run_command/failed_tests_summary'

module CircleCI
  module CLI
    module Command
      class RunCommand < BaseCommand
        API_URL = 'https://circleci.com/api/v3'
        UUID = /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i
        JOB_FETCH_LIMIT = 4

        def self.run(run_id, failed_tests: false)
          raise Thor::Error, 'Run ID must be a UUID.' unless UUID.match?(run_id)

          new(setup_token).summary(run_id, failed_tests:)
        end

        def initialize(token)
          super()
          @headers = { 'Authorization' => "Bearer #{token}" }
        end

        def summary(run_id, failed_tests: false)
          title, workflow_list = Networking::HTTPClient::Session.open(max_retries: 1) do |session|
            [run_title(session, run_id), workflows(session, run_id)]
          end
          groups = fetch_workflow_jobs(workflow_list)
          table = Terminal::Table.new(title:, headings: ['Workflow', 'Job', 'Status', 'Job Number'],
                                      rows: summary_rows(groups)).to_s
          return table unless failed_tests

          tests = FailedTestsSummary.new { |job_id| request("jobs/#{job_id}/tests") }
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

        def fetch_workflow_jobs(workflows)
          pending = Queue.new(workflows.each_with_index).tap(&:close)
          results = Array.new(workflows.size)
          workers = Array.new([workflows.size, JOB_FETCH_LIMIT].min) do
            Thread.new { fetch_pending_jobs(pending, results) }
          end
          workers.each(&:join)
          results.each { |result| raise result if result.is_a?(StandardError) }
        end

        def fetch_pending_jobs(pending, results)
          Networking::HTTPClient::Session.open(max_retries: 1) do |session|
            while (entry = pending.pop)
              workflow, index = entry
              results[index] = workflow_jobs(session, workflow)
            end
          rescue StandardError => e
            pending.clear
            results[index] = e
          end
        end

        def workflows(session, run_id)
          query = { 'filter[run_id]' => run_id }
          results = []
          loop do
            page = get(session, 'workflows', query)
            results.concat(page.fetch('data'))
            cursor = page.fetch('page').fetch('next')
            return results unless cursor

            query['page[cursor]'] = cursor
          end
        end

        def workflow_jobs(session, workflow)
          jobs = get(session, 'jobs', 'filter[workflow_id]' => workflow.fetch('id')).fetch('data')
          [workflow.fetch('attributes').fetch('name'), jobs]
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

        def get(session, path, query = nil)
          JSON.parse(request(path, query, client: session).body)
        rescue JSON::ParserError
          raise Thor::Error, 'CircleCI API returned invalid JSON.'
        end

        def request(path, query = nil, client: Networking::HTTPClient)
          url = "#{API_URL}/#{path}"
          url += "?#{URI.encode_www_form(query)}" if query
          response = client.get_raw(url, @headers)
          return response if response.is_a?(Net::HTTPSuccess)

          raise Thor::Error, api_error(response)
        rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, SocketError, EOFError,
               Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ETIMEDOUT, Errno::EPIPE => e
          raise Thor::Error, "CircleCI API request failed (GET #{url}): #{e.message}"
        end

        def api_error(response)
          message = "CircleCI API error (HTTP #{response.code})"
          error = JSON.parse(response.body.to_s).then { |body| body['error'] if body.is_a?(Hash) }
          detail = error.values_at('detail', 'title').grep(String).find { !_1.strip.empty? } if error.is_a?(Hash)
          detail ? "#{message}: #{Printer.escape_controls(detail)}" : message
        rescue JSON::ParserError
          message
        end
      end
    end
  end
end
