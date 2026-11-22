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
        { 'message' => "first\r\n\r\nline\e[A\r\e[2K" },
        { 'message' => "#{'a' * 121}\n界", 'metadata' => ['}]"', { 'nested' => true }] }
      ]
    end
    let(:response_body) { JSON.generate(output) }

    before do
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:read_body) do |&read|
        response_body.bytes.each { |byte| read.call(byte.chr) }
      end
      allow(http).to receive(:max_retries=).with(0)
      allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:request).with(an_instance_of(Net::HTTP::Get).and(have_attributes(path: '/output/123')))
        .and_yield(response)
    end

    it 'normalizes and joins log messages' do
      expect(log).to eq("first\n\nline\n#{'a' * 121}\n界")
    end

    context 'with an empty log array' do
      let(:output) { [] }

      it 'returns an empty log' do
        expect(log).to eq('')
      end
    end

    {
      'a truncated log array' => '[{"message":"first"}',
      'a trailing comma' => '[{"message":"first"},]',
      'a non-object record' => '[42]',
      'data after the closing bracket' => '[]{}'
    }.each do |description, body|
      context "with #{description}" do
        let(:response_body) { body }

        it 'raises a parse error' do
          expect { log }.to raise_error(JSON::ParserError, 'Invalid action log JSON array')
        end
      end
    end

    context 'without an output URL' do
      let(:attributes) { {} }

      it 'returns no log without making a request' do
        expect(log).to be_nil
        expect(Net::HTTP).not_to have_received(:start)
      end
    end

    context 'with an empty output URL' do
      let(:attributes) { { 'output_url' => '' } }

      it 'returns no log without making a request' do
        expect(log).to be_nil
        expect(Net::HTTP).not_to have_received(:start)
      end
    end
  end
end
