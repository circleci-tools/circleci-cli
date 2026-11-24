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

  describe CircleCI::CLI::Networking::HTTPClient::SessionPool do
    let(:session_class) { CircleCI::CLI::Networking::HTTPClient::Session }

    def stub_session
      instance_double(session_class, close: nil)
    end

    it 'reuses one session for repeated requests to the same origin' do
      session = stub_session
      allow(session_class).to receive(:new).and_return(session)
      expect(session).to receive(:get_raw).with('https://example.com/a', {})
      expect(session).to receive(:get_raw).with('https://example.com/b', {})

      described_class.open do |pool|
        pool.get_raw('https://example.com/a')
        pool.get_raw('https://example.com/b')
      end

      expect(session_class).to have_received(:new).once
    end

    it 'opens a separate scoped session for a different origin' do
      first = stub_session
      second = stub_session
      allow(session_class).to receive(:new).and_return(first, second)
      expect(first).to receive(:get_raw).with('https://example.com/a', { 'Authorization' => 'token' })
      expect(second).to receive(:get_raw).with('https://other.example.com/b', {})

      described_class.open do |pool|
        pool.get_raw('https://example.com/a', 'Authorization' => 'token')
        pool.get_raw('https://other.example.com/b')
      end

      expect(first).to have_received(:close)
      expect(second).to have_received(:close)
    end

    it 'evicts the least recently used origin once the bound is exceeded' do
      first = stub_session
      second = stub_session
      third = stub_session
      allow(session_class).to receive(:new).and_return(first, second, third)
      allow(first).to receive(:get_raw)
      allow(second).to receive(:get_raw)
      allow(third).to receive(:get_raw)

      described_class.open(limit: 2) do |pool|
        pool.get_raw('https://a.example.com/')
        pool.get_raw('https://b.example.com/')
        pool.get_raw('https://c.example.com/')
      end

      expect(first).to have_received(:close)
      expect(second).to have_received(:close)
      expect(third).to have_received(:close)
    end

    it 'closes every open session when the block raises' do
      session = stub_session
      allow(session_class).to receive(:new).and_return(session)
      allow(session).to receive(:get_raw).and_raise(Net::OpenTimeout)

      expect do
        described_class.open { |pool| pool.get_raw('https://example.com/a') }
      end.to raise_error(Net::OpenTimeout)

      expect(session).to have_received(:close)
    end
  end

  describe '.post_form' do
    let(:url) { 'https://example.com/auth' }
    let(:http) { instance_double(Net::HTTP) }
    let(:response) { instance_double(Net::HTTPOK, body: '{"auth":"signed"}') }

    it 'posts params and parses the JSON response body' do
      expect(Net::HTTP).to receive(:start).with('example.com', 443, use_ssl: true).and_yield(http)
      expect(http).to receive(:request)
        .with(an_instance_of(Net::HTTP::Post).and(have_attributes(body: 'socket_id=id&channel_name=channel')))
        .and_return(response)

      result = described_class.post_form(url, socket_id: 'id', channel_name: 'channel')

      expect(result).to eq('auth' => 'signed')
    end
  end
end
