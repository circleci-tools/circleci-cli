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
    let(:http) { instance_double(Net::HTTP) }
    let(:output) do
      [
        { 'message' => "first\r\nline\e[A\r\e[2K" },
        { 'message' => 'a' * 121 }
      ]
    end

    before do
      allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:request).with(an_instance_of(Net::HTTP::Get).and(have_attributes(path: '/output/123')))
        .and_return(instance_double(Net::HTTPOK, body: JSON.generate(output)))
    end

    it 'normalizes and joins log messages' do
      expect(log).to eq(["first\nline", 'a' * 120, 'a'].join("\n"))
    end

    context 'without an output URL' do
      let(:attributes) { {} }

      it 'returns no log without making a request' do
        expect(log).to be_nil
        expect(Net::HTTP).not_to have_received(:start)
      end
    end
  end
end
