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

  it 'reports an empty run' do
    stub_get("runs/#{run_id}", fixtures.fetch('run'))
    stub_get(workflows_path, { 'data' => [], 'page' => { 'next' => nil } })

    expect { described_class.start(['run', run_id]) }.to output(/No workflows found/).to_stdout
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
