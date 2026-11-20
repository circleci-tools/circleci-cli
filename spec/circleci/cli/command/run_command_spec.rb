# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Runner, 'run' do
  let(:client) { CircleCI::CLI::Networking::HTTPClient }
  let(:fixtures) { JSON.parse(File.read(File.expand_path('../../../fixtures/run_responses.json', __dir__))) }
  let(:run_id) { fixtures.fetch('run').fetch('data').fetch('id') }
  let(:headers) { { 'Authorization' => 'Bearer test-token' } }
  let(:workflows_path) { "workflows?filter%5Brun_id%5D=#{run_id}" }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('CIRCLE_CI_TOKEN', nil).and_return('test-token')
  end

  def stub_get(path, body, response_class: Net::HTTPOK, code: '200')
    response = response_class.new('1.1', code, '')
    allow(response).to receive(:body).and_return(JSON.generate(body))
    allow(client).to receive(:get_raw).with("https://circleci.com/api/v3/#{path}", headers).and_return(response)
  end

  it 'shows jobs grouped by workflow across pages, including approvals without a job number' do
    stub_get("runs/#{run_id}", fixtures.fetch('run'))
    stub_get(workflows_path, fixtures.fetch('workflows_first_page'))
    stub_get("#{workflows_path}&page%5Bcursor%5D=cursor%2B%2F%3D", fixtures.fetch('workflows_last_page'))
    { 'checks' => 'first', 'deploy' => 'last' }.each do |name, page|
      workflow = fixtures.fetch("workflows_#{page}_page").fetch('data').first
      stub_get("jobs?filter%5Bworkflow_id%5D=#{workflow.fetch('id')}", fixtures.fetch("#{name}_jobs"))
    end

    expected = <<~TABLE
      +------------------------------------------------------+
      |                  Run #123 (started)                  |
      +----------+---------+--------------------+------------+
      | Workflow | Job     | Status             | Job Number |
      +----------+---------+--------------------+------------+
      | checks   | test    | failed             | 42         |
      | checks   | lint    | running            | 43         |
      | deploy   | approve | waiting (approval) | -          |
      +----------+---------+--------------------+------------+
    TABLE

    expect { described_class.start(['run', run_id]) }.to output(expected).to_stdout
  end

  it 'escapes terminal controls in the title and job rows' do
    run = fixtures.fetch('run')
    run.fetch('data').fetch('attributes').merge!('number' => "123\r", 'phase' => "started\t")
    workflows = fixtures.fetch('workflows_first_page')
    workflows.fetch('page')['next'] = nil
    workflow = workflows.fetch('data').first
    workflow.fetch('attributes')['name'] = "checks\r"
    jobs = fixtures.fetch('checks_jobs')
    jobs.fetch('data').first.fetch('attributes').merge!(
      'name' => "test\e", 'outcome' => "failed\n", 'number' => "42\b"
    )
    stub_get("runs/#{run_id}", run)
    stub_get(workflows_path, workflows)
    stub_get("jobs?filter%5Bworkflow_id%5D=#{workflow.fetch('id')}", jobs)

    expected = <<~'TABLE'
      +-------------------------------------------------+
      |           Run #123\x0D (started\x09)            |
      +------------+----------+------------+------------+
      | Workflow   | Job      | Status     | Job Number |
      +------------+----------+------------+------------+
      | checks\x0D | test\x1B | failed\x0A | 42\x08     |
      | checks\x0D | lint     | running    | 43         |
      +------------+----------+------------+------------+
    TABLE

    expect { described_class.start(['run', run_id]) }.to output(expected).to_stdout
  end

  it 'reports an empty run' do
    stub_get("runs/#{run_id}", fixtures.fetch('run'))
    stub_get(workflows_path, { 'data' => [], 'page' => { 'next' => nil } })

    expect { described_class.start(['run', run_id]) }.to output(/No workflows found/).to_stdout
  end

  it 'rejects an invalid run ID without prompting for a token or requesting the API' do
    expect(CircleCI::CLI::Command::RunCommand).not_to receive(:setup_token)
    expect(client).not_to receive(:get_raw)

    expect do
      expect { described_class.start(%w[run 123]) }.to raise_error(SystemExit) { |error|
        expect(error.status).to eq(1)
      }
    end.to output("Run ID must be a UUID.\n").to_stderr
  end

  it 'reports API failures on stderr and exits unsuccessfully' do
    stub_get("runs/#{run_id}", { 'error' => { 'detail' => 'Run not found' } },
             response_class: Net::HTTPNotFound, code: '404')

    expect do
      expect { described_class.start(['run', run_id]) }.to raise_error(SystemExit) { |error|
        expect(error.status).not_to be_zero
      }
    end.to output("CircleCI API error (HTTP 404): Run not found\n").to_stderr
  end

  it 'reports invalid JSON in a successful API response' do
    response = Net::HTTPOK.new('1.1', '200', '')
    allow(response).to receive(:body).and_return('<html>Invalid response</html>')
    allow(client).to receive(:get_raw).with("https://circleci.com/api/v3/runs/#{run_id}", headers).and_return(response)

    expect do
      expect { described_class.start(['run', run_id]) }.to raise_error(SystemExit) { |error|
        expect(error.status).not_to be_zero
      }
    end.to output("CircleCI API returned invalid JSON.\n").to_stderr
  end

  context 'when a request times out' do
    let(:run_path) { "runs/#{run_id}" }

    {
      Net::OpenTimeout => ['connection timed out', :run_path],
      Net::ReadTimeout => ['read timed out', :workflows_path]
    }.each do |exception, (message, path)|
      it "reports #{exception} on stderr and exits unsuccessfully" do
        stub_get(run_path, fixtures.fetch('run')) if path == :workflows_path
        url = "https://circleci.com/api/v3/#{public_send(path)}"
        timeout = exception.new(message)
        allow(client).to receive(:get_raw).with(url, headers).and_raise(timeout)

        expect do
          expect { described_class.start(['run', run_id]) }.to raise_error(SystemExit) { |error|
            expect(error.status).not_to be_zero
          }
        end.to output("CircleCI API request failed (GET #{url}): #{timeout.message}\n").to_stderr
      end
    end
  end

  it 'reports the HTTP status when an API failure has an invalid JSON body' do
    response = Net::HTTPBadGateway.new('1.1', '502', '')
    allow(response).to receive(:body).and_return('<html>Bad gateway</html>')
    allow(client).to receive(:get_raw).with("https://circleci.com/api/v3/runs/#{run_id}", headers).and_return(response)

    expect do
      expect { described_class.start(['run', run_id]) }.to raise_error(SystemExit) { |error|
        expect(error.status).not_to be_zero
      }
    end.to output("CircleCI API error (HTTP 502)\n").to_stderr
  end
end
