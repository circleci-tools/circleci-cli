# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Response::Action do
  describe '#log' do
    subject(:log) { described_class.new(attributes).log }

    let(:attributes) do
      {
        'output_url' => 'https://circleci.com/output/123'
      }
    end
    let(:http_client) { CircleCI::CLI::Networking::HTTPClient }
    let(:output) do
      [
        { 'message' => "first\r\n\r\nline\e[A\r\e[2K" },
        { 'message' => "#{'a' * 121}\n" }
      ]
    end

    before do
      allow(http_client).to receive(:get)
        .with('https://circleci.com/output/123')
        .and_return(output)
    end

    it 'normalizes and joins log messages' do
      expect(log).to eq("first\n\nline\n#{'a' * 121}\n")
      expect(http_client).to have_received(:get)
    end
  end
end
