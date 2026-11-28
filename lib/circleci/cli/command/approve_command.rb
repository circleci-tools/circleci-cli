# frozen_string_literal: true

require 'circleci/cli/command/run_lookup'

module CircleCI
  module CLI
    module Command
      class ApproveCommand < RunLookup
        PendingApproval = Data.define(:workflow_name, :job)

        def self.run(run_id, job: nil)
          raise Thor::Error, 'Run ID must be a UUID.' unless UUID.match?(run_id)

          new(setup_token).approve(run_id, job:)
        end

        def approve(run_id, job:)
          pending = pending_approvals(run_id)
          job ? approve_job(pending, job) : render(pending)
        end

        private

        def pending_approvals(run_id)
          run_jobs(run_id).flat_map do |workflow_name, jobs|
            jobs.select { |job| pending?(job.fetch('attributes')) }
                .map { |job| PendingApproval.new(workflow_name, job) }
          end
        end

        def pending?(attributes)
          attributes['type'] == 'approval' && attributes['phase'] == 'waiting'
        end

        def approve_job(pending, job)
          approval = matching_approval(pending, job)
          job_id = approval.job.fetch('id')
          Networking::HTTPClient::Session.open(max_retries: 1) do |session|
            post(session, "approvals/#{job_id}/approve")
          end
          "Approved #{Printer.escape_controls(job)} in workflow #{Printer.escape_controls(approval.workflow_name)}."
        end

        def matching_approval(pending, job)
          matches = pending.select { |approval| approval.job.fetch('attributes').fetch('name') == job }
          raise Thor::Error, "No pending approval job named #{job.inspect} found." if matches.empty?
          raise Thor::Error, "Multiple pending approval jobs named #{job.inspect} found." if matches.size > 1

          matches.first
        end

        def render(pending)
          return 'No pending approval jobs found.' if pending.empty?

          rows = pending.map do |approval|
            name = approval.job.fetch('attributes').fetch('name')
            [approval.workflow_name, name].map { |cell| Printer.escape_controls(cell) }
          end
          Terminal::Table.new(headings: %w[Workflow Job], rows:).to_s
        end
      end
    end
  end
end
