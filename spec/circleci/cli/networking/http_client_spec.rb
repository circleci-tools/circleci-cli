# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Networking::HTTPClient, type: :networking do
  describe '.get' do
    let(:url) { 'https://example.com/api/v1/me' }
    let(:uri) { URI(url) }
    let(:request) { instance_double(Net::HTTP::Get) }
    let(:http) { instance_double(Net::HTTP) }
    let(:response) { instance_double(Net::HTTPOK, body: '{"name":"owner"}') }

    it 'sends headers and parses the JSON response body' do
      allow(Net::HTTP::Get).to receive(:new).with(uri).and_return(request)
      allow(request).to receive(:[]=)
      expect(request).to receive(:[]=).with('Circle-Token', 'token')
      expect(Net::HTTP).to receive(:start).with('example.com', 443, use_ssl: true).and_yield(http)
      expect(http).to receive(:request).with(request).and_return(response)

      result = described_class.get(url, 'Circle-Token' => 'token')

      expect(result).to eq('name' => 'owner')
    end
  end

  describe '.get_raw' do
    let(:url) { 'https://example.com/output' }
    let(:http) { instance_double(Net::HTTP) }

    before do
      allow(Net::HTTP).to receive(:start).with('example.com', 443, use_ssl: true).and_yield(http)
    end

    it 'returns the partial HTTP response without parsing it as JSON' do
      response = Net::HTTPPartialContent.new('1.1', '206', 'Partial Content')
      expect(http).to receive(:request).with(satisfy { |request| request['Range'] == 'bytes=13-' })
                                       .and_return(response)

      expect(described_class.get_raw(url, 'Range' => 'bytes=13-')).to be(response)
    end
  end

  describe '.post_form' do
    let(:url) { 'https://example.com/auth' }
    let(:uri) { URI(url) }
    let(:response) { instance_double(Net::HTTPOK, body: '{"auth":"signed"}') }

    it 'posts params and parses the JSON response body' do
      expect(Net::HTTP).to receive(:post_form)
        .with(uri, { socket_id: 'id', channel_name: 'channel' })
        .and_return(response)

      result = described_class.post_form(url, socket_id: 'id', channel_name: 'channel')

      expect(result).to eq('auth' => 'signed')
    end
  end
end
