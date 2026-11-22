# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::RetryCommand, type: :command do
  let(:runner) { CircleCI::CLI::Runner }
  let(:project_path) { '/api/v1.1/project/github/owner/repo' }
  let(:workflow_id) { 'a063aeae-5b89-458b-8aa1-cca4c565b07d' }
  let(:first_job_id) { '981f2bfa-3c50-4505-865d-5266670217eb' }
  let(:last_job_id) { '7e92fbf5-8111-430b-8e2a-54b169ba745d' }
  let(:rerun_id) { '0e53027b-521a-4c40-9042-47e72b3c63a3' }
  let(:rerun_path) { "/api/v2/workflow/#{workflow_id}/rerun" }
  let(:http) { instance_double(Net::HTTP) }

  before do
    allow(ENV).to receive(:fetch).with('CIRCLE_CI_TOKEN', nil).and_return(io_response_circle_ci_token)
    allow_any_instance_of(CircleCi::Build).to receive(:get).and_call_original
    allow_any_instance_of(CircleCi::Project).to receive(:recent_builds).and_call_original
    allow(Net::HTTP).to receive(:new).with('circleci.com', 443, nil, nil, nil, nil).and_return(http)
    allow(http).to receive(:start).and_yield(http)
  end

  it 'reruns the job for the requested build number in a multi-job workflow' do
    expect(described_class).not_to receive(:ask).with('Input build number')
    expect_request('GET', "#{project_path}/42", workflow_build(42, first_job_id))
    expect_request('POST', rerun_path, { workflow_id: rerun_id }, status: '202', payload: { 'jobs' => [first_job_id] })

    expect { runner.start(%w[retry -p owner/repo -n 42]) }
      .to output("workflow #{rerun_id} is triggered for build owner/repo 42\n").to_stdout
  end

  it 'reruns the latest failed job in the same workflow' do
    expect(described_class).not_to receive(:ask).with('Input build number')
    failed_builds = [workflow_build(42, first_job_id), workflow_build(44, last_job_id), { build_num: 43 }]
    expect_request('GET', "#{project_path}?filter=failed", failed_builds)
    expect_request('GET', "#{project_path}/44", workflow_build(44, last_job_id))
    expect_request('POST', rerun_path, { workflow_id: rerun_id }, status: '202', payload: { 'jobs' => [last_job_id] })

    expect { runner.start(%w[retry -p owner/repo --last]) }
      .to output("workflow #{rerun_id} is triggered for build owner/repo 44\n").to_stdout
  end

  it 'reports when there are no failed builds' do
    expect_request('GET', "#{project_path}?filter=failed", [])

    expect(described_class).to receive(:say).with('No failed build found.')

    runner.start(%w[retry -p owner/repo --last])
  end

  it 'fails before posting when the build lacks job metadata' do
    expect_request('GET', "#{project_path}/42", { build_num: 42, workflows: { workflow_id: } })

    expect_retry_failure('The selected build is missing its workflow or job ID.')
  end

  it 'reports an API error from the rerun endpoint' do
    expect_request('GET', "#{project_path}/42", workflow_build(42, first_job_id))
    expect_request('POST', rerun_path, { message: 'Forbidden' }, status: '403', payload: { 'jobs' => [first_job_id] })

    expect_retry_failure('CircleCI API error (HTTP 403): Forbidden')
  end

  it 'fails when the accepted response lacks a workflow ID' do
    expect_request('GET', "#{project_path}/42", workflow_build(42, first_job_id))
    expect_request('POST', rerun_path, {}, status: '202', payload: { 'jobs' => [first_job_id] })

    expect_retry_failure('CircleCI rerun response did not include a workflow ID.')
  end

  def workflow_build(number, job_id)
    { build_num: number, workflows: { workflow_id:, job_id: } }
  end

  def expect_request(method, path, body, status: '200', payload: nil)
    expect(http).to receive(:request).with(have_attributes(method:, path:), nil).ordered do |request, _body|
      expect(request['Circle-Token']).to eq(io_response_circle_ci_token)
      if payload
        expect(request['Content-Type']).to eq('application/json')
        expect(JSON.parse(request.body)).to eq(payload)
      end
      double('HTTP response', code: status, body: JSON.generate(body))
    end
  end

  def expect_retry_failure(message)
    expect do
      expect { runner.start(%w[retry -p owner/repo -n 42]) }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("#{message}\n").to_stderr
  end
end
