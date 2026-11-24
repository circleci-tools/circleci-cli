# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

describe CircleCI::CLI::Runner, 'artifacts' do
  let(:client) { CircleCI::CLI::Networking::HTTPClient }
  let(:session) { instance_double(client::Session, close: nil) }
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
    allow(client).to receive(:get_raw).with(download_url, request_headers).and_yield(response)
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
    expect(client).not_to receive(:get_raw)

    expect { described_class.start(args) }.to output(/checks.*browser-tests.*0.*failure\.png.*1.*failure\.png/m)
      .to_stdout
  end

  it 'streams matching paths into separate directories for parallel executions' do
    other_url = url.sub('/0/', '/1/')
    stub_artifacts(artifact(0), artifact(1, url: other_url), artifact(0, path: 'report.xml'))
    stub_download(url, "first\x00".b)
    stub_download(other_url, 'second')

    Dir.mktmpdir do |destination|
      expect { described_class.start(download_args(destination)) }.to output(/Downloaded 2 artifacts/).to_stdout
      expect(File.binread(File.join(destination, job_id, '0', path))).to eq("first\x00".b)
      expect(File.binread(File.join(destination, job_id, '1', path))).to eq('second')
    end
  end

  it 'reports an unmatched download filter without creating the destination' do
    stub_artifacts(artifact(0))
    expect(client).not_to receive(:get_raw)

    Dir.mktmpdir do |directory|
      destination = File.join(directory, 'artifacts')
      expect { described_class.start(download_args(destination, filter: '*.xml')) }
        .to output("No artifacts matched the download filter.\n").to_stdout
      expect(File.exist?(destination)).to be(false)
    end
  end

  it 'follows a redirect to storage without forwarding the API token' do
    stub_artifacts(artifact(0))
    storage_url = 'https://storage.example.com/signed-download'
    response = Net::HTTPFound.new('1.1', '302', 'Found')
    response['Location'] = storage_url
    allow(client).to receive(:get_raw).with(url, headers).and_yield(response)
    stub_download(storage_url, 'downloaded', request_headers: {})

    Dir.mktmpdir do |destination|
      expect { described_class.start(download_args(destination)) }.to output(/Downloaded 1 artifact/).to_stdout
      expect(File.binread(File.join(destination, job_id, '0', path))).to eq('downloaded')
    end
  end

  it 'reports a malformed artifact URL without exposing the URL or its signing parameters' do
    bad_url = 'https://output.circle-artifacts.com/0/failure.png?X-Amz-Signature=dummy secret'
    stub_artifacts(artifact(0, url: bad_url))
    expect(client).not_to receive(:get_raw)

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
    allow(client).to receive(:get_raw).with(url, headers).and_yield(response)

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

  it 'reports HTTP download errors and leaves no file' do
    stub_artifacts(artifact(0))
    response = Net::HTTPForbidden.new('1.1', '403', 'Forbidden')
    allow(client).to receive(:get_raw).with(url, headers).and_yield(response)

    Dir.mktmpdir do |destination|
      expect { described_class.start(download_args(destination)) }.to output(/Could not download .*HTTP 403/).to_stderr
        .and raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      expect(Dir.children(File.join(destination, job_id, '0', 'screenshots'))).to be_empty
    end
  end

  it 'cleans up an interrupted transfer and preserves the existing file' do
    stub_artifacts(artifact(0))
    response = stub_download(url, '')
    allow(response).to receive(:read_body) do |file|
      file << 'partial'
      raise EOFError, 'unexpected EOF'
    end

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
    expect(client).not_to receive(:get_raw)

    Dir.mktmpdir do |destination|
      expect { described_class.start(download_args(destination, filter: '../*.png')) }
        .to output(/Unsafe artifact path/).to_stderr.and raise_error(SystemExit)
      expect(Dir.children(destination)).to be_empty
    end
  end

  it 'rejects symlink directories beneath the destination' do
    stub_artifacts(artifact(0))
    expect(client).not_to receive(:get_raw)

    Dir.mktmpdir do |destination|
      Dir.mktmpdir do |outside|
        File.symlink(outside, File.join(destination, job_id))
        expect { described_class.start(download_args(destination)) }
          .to output(/Artifact directory is a symlink/).to_stderr.and raise_error(SystemExit)
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
