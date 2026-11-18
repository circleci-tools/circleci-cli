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
end
