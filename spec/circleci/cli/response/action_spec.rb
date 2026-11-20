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

    before do
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:read_body) do |&read|
        JSON.generate(output).bytes.each { |byte| read.call(byte.chr) }
      end
      allow(http).to receive(:max_retries=).with(0)
      allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:request).with(an_instance_of(Net::HTTP::Get).and(have_attributes(path: '/output/123')))
        .and_yield(response)
    end

    it 'normalizes and joins log messages' do
      expect(log).to eq("first\n\nline\n#{'a' * 121}\n界")
    end
  end
end
