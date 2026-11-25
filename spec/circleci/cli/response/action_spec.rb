# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Response::Action do
  describe '#log' do
    subject(:log) { described_class.new(attributes).log }

    let(:attributes) do
      {
        'end_time' => '2026-11-23T00:00:00Z',
        'output_url' => 'https://storage.example.test/output/123?signature=a%2Bb%2Fc%3D&expires=60'
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
      allow(http).to receive(:finish)
      allow(Net::HTTP).to receive(:start).with('storage.example.test', 443, use_ssl: true).and_return(http)
      path = '/output/123?signature=a%2Bb%2Fc%3D&expires=60'
      allow(http).to receive(:request).with(an_instance_of(Net::HTTP::Get).and(have_attributes(path:))).and_yield(response)
    end

    it 'streams and normalizes log messages from a signed HTTPS URL' do
      expect(log).to eq("first\n\nline\n#{'a' * 121}\n界")
    end

    {
      'a plain HTTP URL' => 'http://storage.example.test/output?signature=secret',
      'a malformed URL' => 'https://bad host/output?signature=secret',
      'an HTTPS URL without a hostname' => 'https:///output?signature=secret',
      'a relative URL' => '//storage.example.test/output?signature=secret',
      'a non-string URL' => 42
    }.each do |description, url|
      context "with #{description}" do
        before { attributes['output_url'] = url }

        it 'rejects the URL before connecting and omits it from the error' do
          expect { log }.to raise_error(Thor::Error, 'Action log URL must be an absolute HTTPS URL with a hostname') do |error|
            expect(error.cause).to be_nil
          end
          expect(Net::HTTP).not_to have_received(:start)
        end
      end
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
