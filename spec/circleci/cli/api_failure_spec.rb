# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Runner do
  describe 'CircleCI API failures' do
    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('CIRCLE_CI_TOKEN', nil).and_return('test-token')
    end

    [
      %w[projects],
      %w[builds -p user/repo --all],
      %w[builds -p user/repo -b main],
      %w[build -p user/repo -n 42],
      %w[build -p user/repo --last],
      %w[retry -p user/repo -n 42],
      %w[retry -p user/repo --last],
      %w[cancel -p user/repo -n 42]
    ].each do |arguments|
      context "when running #{arguments.join(' ')}" do
        { '401' => 'Unauthorized', '404' => 'Not Found' }.each do |status, message|
          context "with HTTP #{status}" do
            let(:http_status) { status }
            let(:error_body) { { 'message' => message } }
            let(:build_hash) { error_body }
            let(:builds_body) { error_body }
            let(:projects_body) { error_body }

            it 'reports the API error on stderr and exits unsuccessfully' do
              expect do
                expect { described_class.start(arguments) }.to raise_error(SystemExit) { |error|
                  expect(error.status).not_to be_zero
                }
              end.to output("CircleCI API error (HTTP #{status}): #{message}\n").to_stderr
            end
          end
        end
      end
    end

    context 'when the API error message contains control characters' do
      let(:http_status) { '403' }
      let(:projects_body) { { 'message' => "Access denied\r\nContact support" } }

      it 'reports the HTTP status and escaped message on stderr and exits unsuccessfully' do
        expect do
          expect { described_class.start(%w[projects]) }.to raise_error(SystemExit) { |error|
            expect(error.status).not_to be_zero
          }
        end.to output("CircleCI API error (HTTP 403): Access denied\\x0D\\x0AContact support\n").to_stderr
      end
    end

    context 'when the API returns a non-JSON error body' do
      let(:http_status) { '502' }

      before do
        response = CircleCi::Response.new(double('HTTP response', code: http_status, body: '<html>Bad Gateway</html>'))
        allow_any_instance_of(CircleCi::Projects).to receive(:get).and_return(response)
      end

      it 'reports the HTTP status on stderr and exits unsuccessfully' do
        expect do
          expect { described_class.start(%w[projects]) }.to raise_error(SystemExit) { |error|
            expect(error.status).not_to be_zero
          }
        end.to output("CircleCI API error (HTTP 502)\n").to_stderr
      end
    end
  end

  describe 'watch Pusher connection failure' do
    it 'reports the failure on stderr, exits unsuccessfully, and disconnects' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('CIRCLE_CI_TOKEN', nil).and_return('test-token')
      expect(CircleCI::CLI::Response::Build).to receive(:branch).with('user', 'repo', 'main').once.and_return([])
      account = circleci_response('pusher_id' => 'pusher-123')
      allow(CircleCi::User).to receive(:new).and_return(double(me: account))

      release_connection = Queue.new
      connecting = Queue.new
      global_channel = instance_double(PusherClient::Channel, dispatch_with_all: nil)
      channel = instance_double(PusherClient::Channel, bind: nil)
      socket = instance_double(PusherClient::Socket, global_channel:)
      networking = CircleCI::CLI::Networking
      allow(networking::VerifiedPusherSocket).to receive(:new).and_return(socket)
      allow(socket).to receive(:connect) do
        connecting << Thread.current
        release_connection.pop
        raise IOError, 'socket closed'
      end
      allow(socket).to receive(:subscribe).with('private-pusher-123')
      allow(socket).to receive(:[]).with('private-pusher-123').and_return(channel)
      expect(socket).to receive(:unsubscribe).with('private-pusher-123').ordered
      expect(socket).to receive(:disconnect).ordered
      expect_any_instance_of(CircleCI::CLI::Command::WatchCommand).to receive(:sleep).with(1).once do
        worker = connecting.pop(timeout: 5)
        expect(worker).to be_a(Thread)
        release_connection << true
        expect(worker.join(5)).to eq(worker)
      end

      expect do
        expect { described_class.start(%w[watch -p user/repo -b main]) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Pusher connection failed: socket closed\n").to_stderr
    end
  end

  describe 'watch account lookup' do
    let(:arguments) { %w[watch -p user/repo -b main] }
    let(:client) { double('Pusher client', connect: nil, poll_connection_error: nil, unsubscribe: nil, disconnect: nil) }
    let(:builds_body) { [] }

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('CIRCLE_CI_TOKEN', nil).and_return('test-token')
      allow(CircleCI::CLI::Networking::CircleCIPusherClient).to receive(:new).and_return(client)
      allow_any_instance_of(CircleCI::CLI::Command::WatchCommand).to receive(:sleep).with(1).and_raise(Interrupt)
    end

    it 'reports a failed account lookup on stderr and exits before subscribing' do
      response = CircleCi::Response.new(double(code: '401', body: '{"message":"Unauthorized"}'))
      allow(CircleCi::User).to receive(:new).and_return(double(me: response))
      expect(client).not_to receive(:bind)

      expect do
        expect { described_class.start(arguments) }.to raise_error(SystemExit) { |error|
          expect(error.status).not_to be_zero
        }
      end.to output("CircleCI API error (HTTP 401): Unauthorized\n").to_stderr
    end

    it 'subscribes to the account channel after a successful lookup' do
      response = circleci_response('pusher_id' => 'pusher-123')
      allow(CircleCi::User).to receive(:new).and_return(double(me: response))
      expect(client).to receive(:bind).with('private-pusher-123', 'call', 'pusher_internal:subscription_succeeded')
      expect(CircleCI::CLI::Command::WatchCommand).to receive(:say).with('Exited')

      described_class.start(arguments)
    end
  end
end
