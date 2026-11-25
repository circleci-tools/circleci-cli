# frozen_string_literal: true

require 'circleci/cli/command/run_command/run_request_pool'
require 'circleci/cli/command/watch_command/request_errors'

module CircleCI
  module CLI
    module Command
      class RunLookup < BaseCommand
        API_URL = 'https://circleci.com/api/v3'
        UUID = /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i

        def initialize(token)
          super()
          @headers = { 'Authorization' => "Bearer #{token}" }
        end

        private

        def run_jobs(run_id)
          workflows = Networking::HTTPClient::Session.open(max_retries: 1) { workflows(_1, run_id) }
          fetch_workflow_jobs(workflows)
        end

        def fetch_workflow_jobs(workflows)
          RunRequestPool.fetch(workflows, &method(:workflow_jobs))
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

        def get(session, path, query = nil)
          JSON.parse(request(path, query, client: session).body)
        rescue JSON::ParserError
          raise Thor::Error, 'CircleCI API returned invalid JSON.'
        end

        def request(path, query = nil, client:, &)
          url = "#{API_URL}/#{path}"
          url += "?#{URI.encode_www_form(query)}" if query
          response = client.get_raw(url, @headers, &)
          return response if response.is_a?(Net::HTTPSuccess)

          raise Thor::Error, api_error(response)
        rescue *WatchRequestErrors::TRANSIENT => e
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
