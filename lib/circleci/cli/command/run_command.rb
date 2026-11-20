# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class RunCommand < BaseCommand
        API_URL = 'https://circleci.com/api/v3'
        UUID = /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i
        JOB_FETCH_LIMIT = 4

        def self.run(run_id)
          raise Thor::Error, 'Run ID must be a UUID.' unless UUID.match?(run_id)

          new(setup_token).summary(run_id)
        end

        def initialize(token)
          super()
          @headers = { 'Authorization' => "Bearer #{token}" }
        end

        def summary(run_id)
          run = get("runs/#{run_id}").fetch('data').fetch('attributes')
          status = run['current_outcome'] || run.fetch('phase')
          title = Printer.escape_controls("Run ##{run.fetch('number')} (#{status})")
          Terminal::Table.new(title:,
                              headings: ['Workflow', 'Job', 'Status', 'Job Number'], rows: summary_rows(run_id)).to_s
        end

        private

        def summary_rows(run_id)
          rows = fetch_workflow_rows(workflows(run_id))
          return [['No workflows found', '-', '-', '-']] if rows.empty?

          rows.map { |row| row.map { |cell| Printer.escape_controls(cell) } }
        end

        def fetch_workflow_rows(workflows)
          pending = Queue.new
          workflows.each_with_index { |workflow, index| pending << [workflow, index] }
          pending.close
          results = Array.new(workflows.size)
          workers = Array.new([workflows.size, JOB_FETCH_LIMIT].min) do
            Thread.new { fetch_pending_rows(pending, results) }
          end
          workers.each(&:join)
          results.flat_map { |result| result.is_a?(StandardError) ? raise(result) : result }
        end

        def fetch_pending_rows(pending, results)
          while (entry = pending.pop)
            workflow, index = entry
            results[index] = workflow_rows_or_error(workflow)
          end
        end

        def workflow_rows_or_error(workflow)
          workflow_rows(workflow)
        rescue StandardError => e
          e
        end

        def workflows(run_id)
          query = { 'filter[run_id]' => run_id }
          results = []
          loop do
            page = get('workflows', query)
            results.concat(page.fetch('data'))
            cursor = page.fetch('page').fetch('next')
            return results unless cursor

            query['page[cursor]'] = cursor
          end
        end

        def workflow_rows(workflow)
          name = workflow.fetch('attributes').fetch('name')
          jobs = get('jobs', 'filter[workflow_id]' => workflow.fetch('id')).fetch('data')
          return [[name, 'No jobs found', '-', '-']] if jobs.empty?

          jobs.map { |job| job_row(name, job.fetch('attributes')) }
        end

        def job_row(workflow_name, job)
          status = job['outcome'] || job.fetch('phase')
          status = "#{status} (approval)" if job['type'] == 'approval'
          [workflow_name, job.fetch('name'), status, job['number'] || '-']
        end

        def get(path, query = nil)
          url = "#{API_URL}/#{path}"
          url += "?#{URI.encode_www_form(query)}" if query
          response = Networking::HTTPClient.get_raw(url, @headers)
          return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

          raise Thor::Error, api_error(response)
        rescue JSON::ParserError
          raise Thor::Error, 'CircleCI API returned invalid JSON.'
        rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, SocketError, EOFError,
               Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ETIMEDOUT, Errno::EPIPE => e
          raise Thor::Error, "CircleCI API request failed (GET #{url}): #{e.message}"
        end

        def api_error(response)
          message = "CircleCI API error (HTTP #{response.code})"
          body = JSON.parse(response.body)
          detail = body.dig('error', 'detail') || body.dig('error', 'title') if body.is_a?(Hash)
          detail.to_s.empty? ? message : "#{message}: #{detail}"
        rescue JSON::ParserError
          message
        end
      end
    end
  end
end
