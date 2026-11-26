# frozen_string_literal: true

require 'socket'
require 'spec_helper'
require 'timeout'
require 'tmpdir'

describe CircleCI::CLI::Runner, 'artifacts' do
  let(:client) { CircleCI::CLI::Networking::HTTPClient }
  let(:session) { instance_double(client::Session, close: nil) }
  let(:download_session) { instance_double(client::Session, close: nil) }
  let(:base) { 'https://circleci.com/api/v3' }
  let(:run_id) { '123e4567-e89b-12d3-a456-426614174000' }
  let(:workflow_id) { '123e4567-e89b-12d3-a456-426614174001' }
  let(:job_id) { '123e4567-e89b-12d3-a456-426614174002' }
  let(:headers) { { 'Authorization' => 'Bearer test-token' } }
  let(:args) { ['artifacts', run_id] }
  let(:path) { 'screenshots/failure.png' }
  let(:url) { 'https://output.circle-artifacts.com/0/failure.png' }

  before do
    allow(CircleCI::CLI::Command::ArtifactsCommand).to receive(:setup_token).and_return('test-token')
    allow(client::Session).to receive(:new).with(max_retries: 1).and_return(session)
    allow(client::Session).to receive(:new).with(max_retries: 0).and_return(download_session)
    stub_api("workflows?filter%5Brun_id%5D=#{run_id}",
             [{ 'id' => workflow_id, 'attributes' => { 'name' => 'checks' } }], 'page' => { 'next' => nil })
    stub_api("jobs?filter%5Bworkflow_id%5D=#{workflow_id}",
             [{ 'id' => job_id, 'attributes' => { 'name' => 'browser-tests' } },
              { 'attributes' => { 'name' => 'approve', 'type' => 'approval' } }])
  end

  def stub_api(endpoint, entries, extra = {})
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:body).and_return(JSON.generate(extra.merge('data' => entries)))
    allow(session).to receive(:get_raw).with("#{base}/#{endpoint}", headers).and_return(response)
  end

  def artifact(execution, path: self.path, url: self.url)
    { 'attributes' => { 'execution' => execution, 'path' => path, 'url' => url } }
  end

  def stub_artifacts(*artifacts)
    stub_api("jobs/#{job_id}/artifacts", artifacts)
  end

  def stub_download(download_url, body, request_headers: headers)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:read_body) { |file| file << body }
    allow(download_session).to receive(:get_raw).with(download_url, request_headers).and_yield(response)
    response
  end

  def download_args(destination, filter: 'screenshots/*.png')
    args + ['--download', filter, '--destination', destination]
  end

  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end

  it 'shows an empty result when no jobs have artifacts' do
    stub_artifacts

    expect { described_class.start(args) }.to output("No artifacts found.\n").to_stdout
  end

  it 'lists paths with their workflow, job, and execution without downloading files' do
    stub_artifacts(artifact(0), artifact(1))
    expect(client::Session).not_to receive(:new).with(max_retries: 0)

    expect { described_class.start(args) }.to output(/checks.*browser-tests.*0.*failure\.png.*1.*failure\.png/m)
      .to_stdout
  end

  it 'overlaps job artifact requests up to four at a time and preserves job order after a held-open response' do
    jobs = (1..8).map { |n| { 'id' => "job-#{n}", 'attributes' => { 'name' => "job-#{n}" } } }
    stub_api("jobs?filter%5Bworkflow_id%5D=#{workflow_id}", jobs)

    responses = (1..8).map do |n|
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return(JSON.generate('data' => [artifact(0, path: "job-#{n}.png")]))
      response
    end

    started = Queue.new
    finished = Queue.new
    first_request = Queue.new
    other_requests = Queue.new
    mutex = Mutex.new
    active = peak = 0
    allow(session).to receive(:get_raw).with(a_string_matching(%r{/jobs/job-\d+/artifacts\z}), headers) do |request_url|
      index = request_url[%r{jobs/job-(\d+)/artifacts\z}, 1].to_i

      mutex.synchronize do
        active += 1
        peak = [peak, active].max
      end
      started << index
      (index == 1 ? first_request : other_requests).pop
      mutex.synchronize { active -= 1 }
      finished << index
      responses[index - 1]
    end

    command = CircleCI::CLI::Command::ArtifactsCommand.new('test-token')
    result = nil
    worker = Thread.new { result = command.artifacts(run_id, download: nil, destination: nil) }
    Timeout.timeout(5) do
      4.times { started.pop }
      7.times { other_requests << true }
      7.times { finished.pop }
    end
    first_request << true
    worker.join

    expect(result.scan(/job-\d+\.png/)).to eq((1..8).map { |n| "job-#{n}.png" })
    expect(peak).to eq(4)
  ensure
    first_request&.close
    other_requests&.close
    worker&.join
  end

  it 'overlaps artifact downloads up to four at a time' do
    artifacts = (1..8).map do |n|
      artifact(0, path: "screenshots/file-#{n}.png", url: "https://host-#{n}.example.com/file-#{n}.png")
    end
    stub_artifacts(*artifacts)

    started = Queue.new
    release = Queue.new
    mutex = Mutex.new
    active = peak = 0
    allow(download_session).to receive(:get_raw) do |request_url, _headers, &block|
      mutex.synchronize do
        active += 1
        peak = [peak, active].max
      end
      started << true
      release.pop
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:read_body) { |file| file << request_url }
      block.call(response)
      mutex.synchronize { active -= 1 }
    end

    command = CircleCI::CLI::Command::ArtifactsCommand.new('test-token')
    result = nil
    worker = nil
    Dir.mktmpdir do |destination|
      worker = Thread.new { result = command.artifacts(run_id, download: 'screenshots/*.png', destination:) }
      Timeout.timeout(5) { 4.times { started.pop } }
      8.times { release << true }
      worker.join

      expect(peak).to eq(4)
      expect(result).to match(/Downloaded 8 artifacts/)
      (1..8).each do |n|
        expect(File.binread(File.join(destination, job_id, '0', 'screenshots', "file-#{n}.png")))
          .to eq("https://host-#{n}.example.com/file-#{n}.png")
      end
    end
  ensure
    started&.close
    release&.close
    worker&.join
  end

  it 'reuses one HTTPS session for two files served from the same origin' do
    other_url = url.sub('/0/', '/1/')
    stub_artifacts(artifact(0), artifact(1, url: other_url), artifact(0, path: 'report.xml'))
    stub_download(url, "first\x00".b)
    stub_download(other_url, 'second')

    Dir.mktmpdir do |destination|
      expect { described_class.start(download_args(destination)) }.to output(/Downloaded 2 artifacts/).to_stdout
      expect(File.binread(File.join(destination, job_id, '0', path))).to eq("first\x00".b)
      expect(File.binread(File.join(destination, job_id, '1', path))).to eq('second')
      expect(client::Session).to have_received(:new).with(max_retries: 0).once
      expect(download_session).to have_received(:close)
    end
  end

  it 'drains an unread error response body so a later download on the reused connection is not corrupted' do
    allow(client::Session).to receive(:new).with(max_retries: 0).and_call_original
    server = TCPServer.new('127.0.0.1', 0)
    allow(Net::HTTP).to receive(:start).with('output.circle-artifacts.com', 443, use_ssl: true) do
      Net::HTTP.new('127.0.0.1', server.addr[1], nil).start
    end

    # Net::HTTP closes its socket whenever the block passed to #request raises (see
    # Net::HTTP#transport_request), so the 403 response forces a reconnect before the
    # second artifact's request; the responder accepts a fresh connection each time.
    sockets = []
    responder = Thread.new do
      2.times do
        socket = server.accept
        sockets << socket
        request_line = socket.gets
        socket.each_line.take_while { |line| line != "\r\n" }
        if request_line.include?('err.png')
          body = 'x' * 50
          socket.write("HTTP/1.1 403 Forbidden\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}")
        else
          socket.write("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nok-content")
        end
      end
    end

    Dir.mktmpdir do |destination|
      Timeout.timeout(5) do
        client::SessionPool.open do |sessions|
          downloader = CircleCI::CLI::Command::ArtifactsCommand::Download.new(destination, {}, sessions)
          artifact_class = CircleCI::CLI::Command::ArtifactsCommand::Artifact
          err = artifact_class.new('checks', 'job', job_id, 0, 'err.png',
                                    'https://output.circle-artifacts.com/0/err.png')
          ok = artifact_class.new('checks', 'job', job_id, 0, 'ok.png',
                                   'https://output.circle-artifacts.com/0/ok.png')

          expect { downloader.save(err) }.to raise_error(Thor::Error, /Could not download .*HTTP 403/)
          downloader.save(ok)
        end
      end
      expect(File.binread(File.join(destination, job_id, '0', 'ok.png'))).to eq('ok-content')
    end
  ensure
    responder&.join
    sockets&.each(&:close)
    server&.close
  end

  it 'reports an unmatched download filter without creating the destination' do
    stub_artifacts(artifact(0))
    expect(client::Session).not_to receive(:new).with(max_retries: 0)

    Dir.mktmpdir do |directory|
      destination = File.join(directory, 'artifacts')
      expect { described_class.start(download_args(destination, filter: '*.xml')) }
        .to output("No artifacts matched the download filter.\n").to_stdout
      expect(File.exist?(destination)).to be(false)
    end
  end

  it 'follows a redirect to its own scoped session without forwarding the API token' do
    stub_artifacts(artifact(0))
    storage_url = 'https://storage.example.com/signed-download'
    response = Net::HTTPFound.new('1.1', '302', 'Found')
    response['Location'] = storage_url
    allow(response).to receive(:body)
    allow(download_session).to receive(:get_raw).with(url, headers).and_yield(response)
    stub_download(storage_url, 'downloaded', request_headers: {})

    Dir.mktmpdir do |destination|
      expect { described_class.start(download_args(destination)) }.to output(/Downloaded 1 artifact/).to_stdout
      expect(File.binread(File.join(destination, job_id, '0', path))).to eq('downloaded')
      expect(client::Session).to have_received(:new).with(max_retries: 0).twice
      expect(download_session).to have_received(:close).twice
    end
  end

  it 'reports a malformed artifact URL without exposing the URL or its signing parameters' do
    bad_url = 'https://output.circle-artifacts.com/0/failure.png?X-Amz-Signature=dummy secret'
    stub_artifacts(artifact(0, url: bad_url))
    expect(client::Session).not_to receive(:new).with(max_retries: 0)

    Dir.mktmpdir do |destination|
      stderr = capture_stderr do
        expect { described_class.start(download_args(destination)) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
      expect(stderr).to match(/Could not download .*Invalid artifact URL/)
      expect(stderr).not_to match(/dummy|secret|X-Amz-Signature|circle-artifacts\.com/)
      expect(Dir.children(File.join(destination, job_id, '0', 'screenshots'))).to be_empty
    end
  end

  it 'reports a malformed redirect target without exposing the URL or its signing parameters' do
    stub_artifacts(artifact(0))
    bad_location = 'https://storage.example.com/signed-download?X-Amz-Signature=dummy secret'
    response = Net::HTTPFound.new('1.1', '302', 'Found')
    response['Location'] = bad_location
    allow(response).to receive(:body)
    allow(download_session).to receive(:get_raw).with(url, headers).and_yield(response)
    expect(download_session).to receive(:close)

    Dir.mktmpdir do |destination|
      stderr = capture_stderr do
        expect { described_class.start(download_args(destination)) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
      expect(stderr).to match(/Could not download .*Invalid artifact redirect URL/)
      expect(stderr).not_to match(/dummy|secret|X-Amz-Signature|storage\.example\.com/)
      expect(Dir.children(File.join(destination, job_id, '0', 'screenshots'))).to be_empty
    end
  end

  it 'reports HTTP download errors, leaves no file, and closes the session' do
    stub_artifacts(artifact(0))
    response = Net::HTTPForbidden.new('1.1', '403', 'Forbidden')
    allow(response).to receive(:body)
    allow(download_session).to receive(:get_raw).with(url, headers).and_yield(response)
    expect(download_session).to receive(:close)

    Dir.mktmpdir do |destination|
      expect { described_class.start(download_args(destination)) }.to output(/Could not download .*HTTP 403/).to_stderr
        .and raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      expect(Dir.children(File.join(destination, job_id, '0', 'screenshots'))).to be_empty
    end
  end

  it 'cleans up an interrupted transfer, preserves the existing file, and closes the session' do
    stub_artifacts(artifact(0))
    response = stub_download(url, '')
    allow(response).to receive(:read_body) do |file|
      file << 'partial'
      raise EOFError, 'unexpected EOF'
    end
    expect(download_session).to receive(:close)

    Dir.mktmpdir do |destination|
      target = File.join(destination, job_id, '0', path)
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, 'previous')
      expect { described_class.start(download_args(destination)) }.to output(/unexpected EOF/).to_stderr
        .and raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      expect(File.read(target)).to eq('previous')
      expect(Dir.children(File.dirname(target))).to eq(['failure.png'])
    end
  end

  it 'rejects unsafe paths before fetching the artifact' do
    stub_artifacts(artifact(0, path: '../escape.png'))
    expect(client::Session).not_to receive(:new).with(max_retries: 0)

    Dir.mktmpdir do |destination|
      expect { described_class.start(download_args(destination, filter: '../*.png')) }
        .to output(/Unsafe artifact path/).to_stderr.and raise_error(SystemExit)
      expect(Dir.children(destination)).to be_empty
    end
  end

  it 'rejects symlink directories beneath the destination' do
    stub_artifacts(artifact(0))
    expect(client::Session).not_to receive(:new).with(max_retries: 0)

    Dir.mktmpdir do |destination|
      Dir.mktmpdir do |outside|
        File.symlink(outside, File.join(destination, job_id))
        expect { described_class.start(download_args(destination)) }
          .to output(/Artifact directory is a symlink/).to_stderr.and raise_error(SystemExit)
        expect(Dir.children(outside)).to be_empty
      end
    end
  end

  it 'keeps a download inside the opened directory when it is swapped for a symlink mid-transfer' do
    stub_artifacts(artifact(0))
    response = stub_download(url, '')

    Dir.mktmpdir do |destination|
      Dir.mktmpdir do |outside|
        screenshots_dir = File.join(destination, job_id, '0', 'screenshots')
        saved_dir = "#{screenshots_dir}.saved"
        allow(response).to receive(:read_body) do |file|
          File.rename(screenshots_dir, saved_dir)
          File.symlink(outside, screenshots_dir)
          file << 'downloaded'
        end

        expect { described_class.start(download_args(destination)) }.to output(/Downloaded 1 artifact/).to_stdout
        expect(File.binread(File.join(saved_dir, 'failure.png'))).to eq('downloaded')
        expect(Dir.children(outside)).to be_empty
      end
    end
  end

  it 'requires a filter and destination together before prompting for a token' do
    expect(CircleCI::CLI::Command::ArtifactsCommand).not_to receive(:setup_token)

    expect { described_class.start(args + ['--destination', 'artifacts']) }
      .to output(/Provide both --download PATH and --destination DIRECTORY/).to_stderr.and raise_error(SystemExit)
  end
end
