# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Runner, 'approve' do
  let(:client) { CircleCI::CLI::Networking::HTTPClient }
  let(:session) { instance_double(client::Session, close: nil) }
  let(:base) { 'https://circleci.com/api/v3' }
  let(:run_id) { '123e4567-e89b-12d3-a456-426614174000' }
  let(:checks_id) { '123e4567-e89b-12d3-a456-426614174001' }
  let(:deploy_id) { '123e4567-e89b-12d3-a456-426614174002' }
  let(:headers) { { 'Authorization' => 'Bearer test-token' } }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('CIRCLE_CI_TOKEN', nil).and_return('test-token')
    allow(client::Session).to receive(:new).with(max_retries: 1).and_return(session)
    stub_api("workflows?filter%5Brun_id%5D=#{run_id}",
             [{ 'id' => checks_id, 'attributes' => { 'name' => 'checks' } },
              { 'id' => deploy_id, 'attributes' => { 'name' => 'deploy' } }], 'page' => { 'next' => nil })
  end

  def stub_api(endpoint, entries, extra = {})
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:body).and_return(JSON.generate(extra.merge('data' => entries)))
    allow(session).to receive(:get_raw).with("#{base}/#{endpoint}", headers).and_return(response)
  end

  def stub_jobs(workflow_id, jobs)
    stub_api("jobs?filter%5Bworkflow_id%5D=#{workflow_id}", jobs)
  end

  def approval_job(name, request_id: 'request-1', phase: 'waiting')
    { 'attributes' => { 'name' => name, 'phase' => phase, 'type' => 'approval', 'approval_request_id' => request_id } }
  end

  def build_job(name, phase: 'ended', outcome: 'success')
    { 'attributes' => { 'name' => name, 'phase' => phase, 'outcome' => outcome, 'type' => 'build' } }
  end

  def stub_post(path, response_class: Net::HTTPOK, code: '200', body: '{}')
    response = response_class.new('1.1', code, '')
    allow(response).to receive(:body).and_return(body)
    allow(session).to receive(:post_raw).with("#{base}/#{path}", headers).and_return(response)
  end

  it 'lists pending approval jobs across workflows, excluding build jobs and already-approved jobs' do
    stub_jobs(checks_id, [build_job('test')])
    stub_jobs(deploy_id, [approval_job('approve'), approval_job('deploy-approve', phase: 'finished')])

    expected = <<~TABLE
      +----------+---------+
      | Workflow | Job     |
      +----------+---------+
      | deploy   | approve |
      +----------+---------+
    TABLE
    expect { described_class.start(['approve', run_id]) }.to output(expected).to_stdout
  end

  it 'reports no pending approval jobs found' do
    stub_jobs(checks_id, [build_job('test')])
    stub_jobs(deploy_id, [])

    expect { described_class.start(['approve', run_id]) }.to output("No pending approval jobs found.\n").to_stdout
  end

  it 'escapes control characters in the listed workflow and job names' do
    stub_api("workflows?filter%5Brun_id%5D=#{run_id}",
             [{ 'id' => checks_id, 'attributes' => { 'name' => 'checks' } },
              { 'id' => deploy_id, 'attributes' => { 'name' => "deplo\ry" } }], 'page' => { 'next' => nil })
    stub_jobs(checks_id, [])
    stub_jobs(deploy_id, [approval_job("appro\eve")])

    expect { described_class.start(['approve', run_id]) }.to output(/deplo\\x0Dy.*appro\\x1Bve/m).to_stdout
  end

  it 'approves the pending job matching the given name' do
    stub_jobs(checks_id, [build_job('test')])
    stub_jobs(deploy_id, [approval_job('approve', request_id: 'req-123')])
    stub_post("workflow/#{deploy_id}/approve/req-123")

    expect { described_class.start(['approve', run_id, '--job', 'approve']) }
      .to output("Approved approve in workflow deploy.\n").to_stdout
    expect(session).to have_received(:post_raw).with("#{base}/workflow/#{deploy_id}/approve/req-123", headers)
  end

  it 'escapes control characters in the approval confirmation message' do
    stub_jobs(checks_id, [])
    stub_jobs(deploy_id, [approval_job("appro\eve", request_id: 'req-123')])
    stub_post("workflow/#{deploy_id}/approve/req-123")

    expect { described_class.start(['approve', run_id, '--job', "appro\eve"]) }
      .to output(/Approved appro\\x1Bve in workflow deploy\./).to_stdout
  end

  it 'reports an error when no pending approval job matches the given name' do
    stub_jobs(checks_id, [build_job('test')])
    stub_jobs(deploy_id, [approval_job('approve')])

    expect do
      expect { described_class.start(['approve', run_id, '--job', 'missing']) }.to raise_error(SystemExit) { |error|
        expect(error.status).not_to be_zero
      }
    end.to output("No pending approval job named \"missing\" found.\n").to_stderr
  end

  it 'reports an error when several pending approval jobs share the given name' do
    stub_jobs(checks_id, [approval_job('approve', request_id: 'req-1')])
    stub_jobs(deploy_id, [approval_job('approve', request_id: 'req-2')])

    expect do
      expect { described_class.start(['approve', run_id, '--job', 'approve']) }.to raise_error(SystemExit) { |error|
        expect(error.status).not_to be_zero
      }
    end.to output("Multiple pending approval jobs named \"approve\" found.\n").to_stderr
    expect(session).not_to have_received(:post_raw)
  end

  it 'reports a CircleCI API error from the approve request on stderr and exits unsuccessfully' do
    stub_jobs(checks_id, [])
    stub_jobs(deploy_id, [approval_job('approve', request_id: 'req-123')])
    stub_post("workflow/#{deploy_id}/approve/req-123", response_class: Net::HTTPForbidden, code: '403',
              body: '{"error":{"detail":"Approval denied"}}')

    expect do
      expect { described_class.start(['approve', run_id, '--job', 'approve']) }.to raise_error(SystemExit) { |error|
        expect(error.status).not_to be_zero
      }
    end.to output("CircleCI API error (HTTP 403): Approval denied\n").to_stderr
  end

  it 'rejects an invalid run ID without prompting for a token or requesting the API' do
    expect(CircleCI::CLI::Command::ApproveCommand).not_to receive(:setup_token)
    expect(client::Session).not_to receive(:new)

    expect do
      expect { described_class.start(%w[approve 123]) }.to raise_error(SystemExit) { |error|
        expect(error.status).to eq(1)
      }
    end.to output("Run ID must be a UUID.\n").to_stderr
  end
end
