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
    let(:http_client) { class_double(CircleCI::CLI::Networking::HTTPClient) }
    let(:output) do
      [
        { 'message' => "first\r\nline\e[A\r\e[2K" },
        { 'message' => 'a' * 121 }
      ]
    end

    before do
      stub_const('CircleCI::CLI::Networking::HTTPClient', http_client)
      allow(http_client).to receive(:get)
        .with('https://circleci.com/output/123')
        .and_return(output)
    end

    it 'normalizes and joins log messages' do
      expect(log).to eq(["first\nline", 'a' * 120, 'a'].join("\n"))
      expect(http_client).to have_received(:get)
    end

    context 'without an output URL' do
      let(:attributes) { {} }

      it 'returns no log without making a request' do
        expect(log).to be_nil
        expect(http_client).not_to have_received(:get)
      end
    end
  end
end
