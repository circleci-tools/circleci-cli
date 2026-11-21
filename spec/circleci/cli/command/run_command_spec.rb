# frozen_string_literal: true

require 'socket'
require 'spec_helper'
require 'timeout'

describe CircleCI::CLI::Runner, 'run' do
  let(:client) { CircleCI::CLI::Networking::HTTPClient }
  let(:session) { instance_double(client::Session, close: nil) }
  let(:fixtures) { JSON.parse(File.read(File.expand_path('../../../fixtures/run_responses.json', __dir__))) }
  let(:run_id) { fixtures.fetch('run').fetch('data').fetch('id') }
  let(:headers) { { 'Authorization' => 'Bearer test-token' } }
  let(:workflows_path) { "workflows?filter%5Brun_id%5D=#{run_id}" }

  before do
    allow(client::Session).to receive(:new).with(max_retries: 1).and_return(session)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('CIRCLE_CI_TOKEN', nil).and_return('test-token')
  end

  def stub_get(path, body, response_class: Net::HTTPOK, code: '200', raw: false)
    response = response_class.new('1.1', code, '')
    allow(response).to receive(:body).and_return(raw ? body : JSON.generate(body))
    transport = path.end_with?('/tests') ? client : session
    allow(transport).to receive(:get_raw).with("https://circleci.com/api/v3/#{path}", headers).and_return(response)
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

  context 'with --failed-tests' do
    let(:args) { ['run', run_id, '--failed-tests'] }
    let(:unit_id) { '123e4567-e89b-12d3-a456-426614174010' }
    let(:integration_id) { '123e4567-e89b-12d3-a456-426614174011' }
    let(:system_id) { '123e4567-e89b-12d3-a456-426614174012' }
    let(:smoke_id) { '123e4567-e89b-12d3-a456-426614174013' }

    before do
      stub_get("runs/#{run_id}", fixtures.fetch('run'))
    end

    def stub_workflow_page(page, jobs, cursor: '')
      response = fixtures.fetch("workflows_#{page}_page")
      stub_get("#{workflows_path}#{cursor}", response)
      workflow_id = response.fetch('data').first.fetch('id')
      stub_get("jobs?filter%5Bworkflow_id%5D=#{workflow_id}", { 'data' => jobs })
    end

    def failed_job(id, name)
      { 'id' => id, 'attributes' => { 'name' => name, 'outcome' => 'failed' } }
    end

    it 'groups failures across workflow pages and distinguishes empty and passing results' do
      lint = fixtures.fetch('checks_jobs').fetch('data').last
      stub_workflow_page('first', [failed_job(unit_id, 'unit'), failed_job(integration_id, 'integration'), lint])
      deploy_jobs = [failed_job(system_id, 'system'), failed_job(smoke_id, 'smoke')]
      stub_workflow_page('last', deploy_jobs, cursor: '&page%5Bcursor%5D=cursor%2B%2F%3D')
      failure = { 'name' => 'rejects an expired token', 'result' => 'failure',
                  'file' => 'spec/token_spec.rb', 'message' => "Expected rejection\nReceived \e success" }
      fileless_failure = { 'name' => 'rejects empty input', 'result' => 'failure', 'message' => 'Expected an error' }
      passing = { 'name' => 'accepts an active token', 'result' => 'success' }
      records = [failure, passing, failure].map { |record| JSON.generate(record) }.join("\n")
      stub_get("jobs/#{unit_id}/tests", records, raw: true)
      stub_get("jobs/#{integration_id}/tests", nil, response_class: Net::HTTPNoContent, code: '204', raw: true)
      stub_get("jobs/#{system_id}/tests", JSON.generate(fileless_failure), raw: true)
      stub_get("jobs/#{smoke_id}/tests", JSON.generate(passing), raw: true)

      expected = <<~'SUMMARY'
        Failed tests

        checks
          unit
            - rejects an expired token (spec/token_spec.rb)
              Expected rejection
              Received \x1B success
            - rejects an expired token (spec/token_spec.rb)
              Expected rejection
              Received \x1B success
          integration
            No uploaded test results.

        deploy
          system
            - rejects empty input
              Expected an error
          smoke
            No failures in uploaded test results.
      SUMMARY
      expect { described_class.start(args) }.to output(/#{Regexp.escape(expected)}\z/).to_stdout
      expect(session).to have_received(:get_raw).with(%r{/jobs\?filter%5Bworkflow_id%5D=}, headers).twice
    end

    it 'reports when no jobs failed' do
      stub_get(workflows_path, { 'data' => [], 'page' => { 'next' => nil } })

      expect { described_class.start(args) }.to output(/No failed jobs found\./).to_stdout
    end

    context 'when results cannot be loaded' do
      before do
        fixtures.fetch('workflows_first_page').fetch('page')['next'] = nil
        stub_workflow_page('first', [failed_job(unit_id, 'unit')])
      end

      it 'reports the failed request and job on stderr and exits unsuccessfully' do
        stub_get("jobs/#{unit_id}/tests", { 'error' => { 'detail' => 'Access denied' } },
                 response_class: Net::HTTPForbidden, code: '403')

        expect do
          expect { described_class.start(args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output("Unable to load test results for job unit (#{unit_id}): " \
                      "CircleCI API error (HTTP 403): Access denied\n").to_stderr
      end

      it 'reports an invalid JSON Lines response' do
        stub_get("jobs/#{unit_id}/tests", "[]\n", raw: true)

        expect do
          expect { described_class.start(args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output("Unable to load test results for job unit (#{unit_id}): " \
                      "CircleCI API returned invalid JSON Lines.\n").to_stderr
      end
    end
  end

  it 'overlaps jobs requests up to four at a time and renders workflows in API order' do
    workflows = (1..8).map { |id| { 'id' => id, 'attributes' => { 'name' => "workflow-#{id}" } } }
    stub_get("runs/#{run_id}", fixtures.fetch('run'))
    stub_get(workflows_path, { 'data' => workflows, 'page' => { 'next' => nil } })

    started = Queue.new
    finished = Queue.new
    first_request = Queue.new
    other_requests = Queue.new
    mutex = Mutex.new
    active = peak = 0
    response = Net::HTTPOK.new('1.1', '200', '')
    allow(response).to receive(:body).and_return(JSON.generate(fixtures.fetch('checks_jobs')))
    allow(session).to receive(:get_raw).with(%r{/jobs\?filter%5Bworkflow_id%5D=\d+\z}, headers) do |url, _headers|
      mutex.synchronize do
        active += 1
        peak = [peak, active].max
      end
      started << url
      (url.end_with?('=1') ? first_request : other_requests).pop
      mutex.synchronize { active -= 1 }
      finished << url
      response
    end

    command = CircleCI::CLI::Command::RunCommand.new('test-token')
    summary = Thread.new { command.summary(run_id) }
    Timeout.timeout(5) do
      4.times { started.pop }
      7.times { other_requests << true }
      7.times { finished.pop }
    end
    first_request << true

    expect(summary.value.scan(/(workflow-\d+)\s+\| (test|lint)/)).to eq(
      (1..8).flat_map { |id| %w[test lint].map { |job| ["workflow-#{id}", job] } }
    )
    expect(peak).to eq(4)
  ensure
    first_request&.close
    other_requests&.close
    summary&.join
  end

  it 'reuses keep-alive connections for workflow pages and for jobs within a worker' do
    server = TCPServer.new('127.0.0.1', 0)
    sockets = []
    allow(client::Session).to receive(:new).with(max_retries: 1).and_call_original
    allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true) do
      Net::HTTP.new('127.0.0.1', server.addr[1], nil).start
    end
    workflows = (1..5).map { |id| { 'id' => id, 'attributes' => { 'name' => "workflow-#{id}" } } }
    command = CircleCI::CLI::Command::RunCommand.new('test-token')
    summary = Thread.new { command.summary(run_id) }

    Timeout.timeout(5) do
      sockets << server.accept
      metadata = sockets.first
      expect(read_request(metadata)).to eq("runs/#{run_id}")
      write_response(metadata, fixtures.fetch('run'))
      expect(read_request(metadata)).to eq(workflows_path)
      write_response(metadata, { 'data' => workflows.first(2), 'page' => { 'next' => 'more' } })
      expect(read_request(metadata)).to eq("#{workflows_path}&page%5Bcursor%5D=more")
      write_response(metadata, { 'data' => workflows.drop(2), 'page' => { 'next' => nil } })
      expect(metadata.read).to eq('')

      4.times { sockets << server.accept }
      workers = sockets.drop(1)
      expect(workers.map { |socket| read_request(socket) }).to match_array(
        (1..4).map { |id| "jobs?filter%5Bworkflow_id%5D=#{id}" }
      )
      jobs = { 'data' => [] }
      write_response(workers.first, jobs)
      expect(read_request(workers.first)).to eq('jobs?filter%5Bworkflow_id%5D=5')
      workers.each { |socket| write_response(socket, jobs) }
      workers.each { |socket| expect(socket.read).to eq('') }
      expect(summary.value.scan(/workflow-\d+/)).to eq((1..5).map { |id| "workflow-#{id}" })
    end
  ensure
    sockets&.each(&:close)
    server&.close
    summary&.kill&.join
  end

  def read_request(socket)
    request_line = socket.gets
    headers = socket.each_line.take_while { |line| line != "\r\n" }
    expect(headers).to include("Authorization: Bearer test-token\r\n")
    request_line.split.fetch(1).delete_prefix('/api/v3/')
  end

  def write_response(socket, payload)
    body = JSON.generate(payload)
    socket.write("HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}")
  end

  it 'reports a jobs API failure on stderr and exits unsuccessfully' do
    stub_get("runs/#{run_id}", fixtures.fetch('run'))
    workflows = %w[first last].flat_map { |page| fixtures.fetch("workflows_#{page}_page").fetch('data') }
    stub_get(workflows_path, { 'data' => workflows, 'page' => { 'next' => nil } })
    first_workflow, last_workflow = workflows
    stub_get("jobs?filter%5Bworkflow_id%5D=#{first_workflow.fetch('id')}", fixtures.fetch('checks_jobs'))
    stub_get("jobs?filter%5Bworkflow_id%5D=#{last_workflow.fetch('id')}", { 'error' => { 'detail' => 'Jobs unavailable' } },
             response_class: Net::HTTPServiceUnavailable, code: '503')

    expect do
      expect { described_class.start(['run', run_id]) }.to raise_error(SystemExit) { |error|
        expect(error.status).not_to be_zero
      }
    end.to output("CircleCI API error (HTTP 503): Jobs unavailable\n").to_stderr
    expect(session).to have_received(:close).exactly(3).times
  end

  it 'stops queued job requests after a failure and waits for requests in flight' do
    workflows = (1..8).map { |id| { 'id' => id, 'attributes' => { 'name' => "workflow-#{id}" } } }
    stub_get("runs/#{run_id}", fixtures.fetch('run'))
    stub_get(workflows_path, { 'data' => workflows, 'page' => { 'next' => nil } })

    started = Queue.new
    failure_worker = Queue.new
    fail_request = Queue.new
    finish_requests = Queue.new
    success = Net::HTTPOK.new('1.1', '200', '')
    allow(success).to receive(:body).and_return(JSON.generate(fixtures.fetch('checks_jobs')))
    failure = Net::HTTPServiceUnavailable.new('1.1', '503', '')
    allow(failure).to receive(:body).and_return('{"error":{"detail":"Jobs unavailable"}}')
    jobs_url = %r{/jobs\?filter%5Bworkflow_id%5D=\d+\z}
    allow(session).to receive(:get_raw).with(jobs_url, headers) do |url, _headers|
      id = url.split('=').last.to_i
      started << id
      if id == 1
        failure_worker << Thread.current
        fail_request.pop
        failure
      else
        finish_requests.pop if id <= 4
        success
      end
    end

    command = CircleCI::CLI::Command::RunCommand.new('test-token')
    summary = Thread.new do
      command.summary(run_id)
    rescue Thor::Error => e
      e
    end
    Timeout.timeout(5) do
      expect(Array.new(4) { started.pop }).to match_array(1..4)
      fail_request << true
      failure_worker.pop.join
      expect(summary).to be_alive
      finish_requests.close
      expect(summary.value).to be_a(Thor::Error)
      expect(summary.value.message).to eq('CircleCI API error (HTTP 503): Jobs unavailable')
    end
    expect(session).to have_received(:get_raw).with(jobs_url, headers).exactly(4).times
  ensure
    fail_request&.close
    finish_requests&.close
    summary&.join
  end

  it 'rejects an invalid run ID without prompting for a token or requesting the API' do
    expect(CircleCI::CLI::Command::RunCommand).not_to receive(:setup_token)
    expect(client::Session).not_to receive(:new)

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
    expect(session).to have_received(:close).once
  end

  it 'reports invalid JSON in a successful API response' do
    response = Net::HTTPOK.new('1.1', '200', '')
    allow(response).to receive(:body).and_return('<html>Invalid response</html>')
    allow(session).to receive(:get_raw).with("https://circleci.com/api/v3/runs/#{run_id}", headers).and_return(response)

    expect do
      expect { described_class.start(['run', run_id]) }.to raise_error(SystemExit) { |error|
        expect(error.status).not_to be_zero
      }
    end.to output("CircleCI API returned invalid JSON.\n").to_stderr
  end

  it 'reports the HTTP status when an API failure has a string error' do
    stub_get("runs/#{run_id}", { 'error' => 'Bad gateway' },
             response_class: Net::HTTPBadGateway, code: '502')

    expect do
      expect { described_class.start(['run', run_id]) }.to raise_error(SystemExit) { |error|
        expect(error.status).not_to be_zero
      }
    end.to output("CircleCI API error (HTTP 502)\n").to_stderr
  end

  it 'reports the error title when the detail is empty' do
    stub_get("runs/#{run_id}", { 'error' => { 'detail' => '', 'title' => 'Bad gateway' } },
             response_class: Net::HTTPBadGateway, code: '502')

    expect do
      expect { described_class.start(['run', run_id]) }.to raise_error(SystemExit) { |error|
        expect(error.status).not_to be_zero
      }
    end.to output("CircleCI API error (HTTP 502): Bad gateway\n").to_stderr
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
        allow(session).to receive(:get_raw).with(url, headers).and_raise(timeout)

        expect do
          expect { described_class.start(['run', run_id]) }.to raise_error(SystemExit) { |error|
            expect(error.status).not_to be_zero
          }
        end.to output("CircleCI API request failed (GET #{url}): #{timeout.message}\n").to_stderr
      end
    end
  end

  [nil, '<html>Bad gateway</html>'].each do |body|
    description = body.nil? ? 'no body' : 'an invalid JSON body'
    it "reports the HTTP status when an API failure has #{description}" do
      response = Net::HTTPBadGateway.new('1.1', '502', '')
      allow(response).to receive(:body).and_return(body)
      allow(session).to receive(:get_raw).with("https://circleci.com/api/v3/runs/#{run_id}", headers).and_return(response)

      expect do
        expect { described_class.start(['run', run_id]) }.to raise_error(SystemExit) { |error|
          expect(error.status).not_to be_zero
        }
      end.to output("CircleCI API error (HTTP 502)\n").to_stderr
    end
  end
end
