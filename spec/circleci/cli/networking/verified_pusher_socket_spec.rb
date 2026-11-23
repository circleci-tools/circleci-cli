# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'timeout'

describe CircleCI::CLI::Networking::VerifiedPusherSocket do
  let(:hostname) { 'localhost' }
  let(:ca_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:server_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:ca) { certificate('Test CA', ca_key) }

  it 'upgrades to WebSocket and dispatches an event with a trusted matching certificate' do
    with_tls_server(hostname) do |client, server|
      messages = []
      client.bind('test:event') { |data| messages << data }

      expect { Timeout.timeout(5) { client.connect } }.to raise_error(EOFError)
      expect(server.value).to start_with('GET /app/test-key?')
      expect(messages).to eq(['connected'])
    end
  end

  it 'rejects a trusted certificate for another hostname before sending the upgrade request' do
    with_tls_server('other.example') do |client, server|
      expect { Timeout.timeout(5) { client.connect } }.to raise_error(OpenSSL::SSL::SSLError, /hostname mismatch/i)
      expect(Timeout.timeout(5) { server.value }).to be_nil
    end
  end

  it 'reports a stalled upgrade in watch, exits with status 1, and closes the connection' do
    stub_const('CircleCI::CLI::Networking::VerifiedPusherWebSocket::CONNECT_TIMEOUT', 1)
    allow(CircleCI::CLI::Command::WatchCommand).to receive(:setup_token).and_return('token')
    allow(CircleCI::CLI::Response::Account).to receive(:me).and_return(double(pusher_id: 'test-id'))
    allow(CircleCI::CLI::Response::Build).to receive(:branch).with('user', 'repo', 'main').and_return([])

    with_tls_server(hostname, stall: true) do |client, server|
      allow(described_class).to receive(:new).and_return(client)
      expect do
        expect { Timeout.timeout(5) { CircleCI::CLI::Runner.start(%w[watch -p user/repo -b main]) } }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Pusher connection failed: Pusher WebSocket handshake timed out\n").to_stderr
      expect(Timeout.timeout(5) { server.value }).to match([a_string_starting_with('GET /app/test-key?'), nil])
    end
  end

  def with_tls_server(certificate_hostname, stall: false)
    listener = TCPServer.new('127.0.0.1', 0)
    port = listener.addr[1]
    context = OpenSSL::SSL::SSLContext.new
    context.cert = certificate(certificate_hostname, server_key, issuer: ca)
    context.key = server_key
    server = Thread.new { receive_upgrade(OpenSSL::SSL::SSLServer.new(listener, context), stall:) }

    Tempfile.create('pusher-ca') do |ca_file|
      ca_file.write(ca.to_pem)
      ca_file.flush
      client = described_class.new(
        'test-key', secure: true, ws_host: hostname, wss_port: port, cert_file: ca_file.path, logger: Logger.new(File::NULL)
      )
      yield client, server
    ensure
      client&.disconnect
    end
  ensure
    server&.kill&.join
    listener&.close
  end

  def receive_upgrade(server, stall:)
    connection = server.accept
    request = connection.gets("\r\n\r\n")
    return if request.nil?
    return [request, connection.getc] if stall

    handshake = WebSocket::Handshake::Server.new
    handshake << request
    connection.write(handshake.to_s)
    data = JSON.generate(event: 'test:event', data: 'connected')
    connection.write(WebSocket::Frame::Outgoing::Server.new(version: handshake.version, data: data, type: :text).to_s)
    request
  rescue OpenSSL::SSL::SSLError
    raise if connection
  ensure
    connection&.close
  end

  def certificate(name, key, issuer: nil)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = issuer ? 2 : 1
    cert.subject = OpenSSL::X509::Name.new([['CN', name]])
    cert.issuer = issuer ? issuer.subject : cert.subject
    cert.public_key = key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    extensions = OpenSSL::X509::ExtensionFactory.new
    if issuer
      cert.add_extension(extensions.create_extension('subjectAltName', "DNS:#{name}"))
    else
      cert.add_extension(extensions.create_extension('basicConstraints', 'CA:TRUE', true))
    end
    cert.sign(ca_key, OpenSSL::Digest.new('SHA256'))
  end
end
