# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Networking::HTTPClient, type: :networking do
  describe CircleCI::CLI::Networking::HTTPClient::SessionPool do
    let(:session_class) { CircleCI::CLI::Networking::HTTPClient::Session }

    def stub_session
      instance_double(session_class, close: nil)
    end

    def wait_until_blocked(thread)
      Timeout.timeout(5) do
        Thread.pass until thread.stop?
        thread.value unless thread.alive?
      end
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

    it 'evicts the oldest idle session while another origin is streaming' do
      active, oldest_idle, *idle_sessions = Array.new(5) { stub_session }
      allow(session_class).to receive(:new).and_return(active, oldest_idle, *idle_sessions)
      allow(active).to receive(:get_raw).and_yield(:response)
      [oldest_idle, *idle_sessions].each { |session| allow(session).to receive(:get_raw) }
      streaming = Queue.new
      finish = Queue.new

      described_class.open do |pool|
        worker = Thread.new do
          pool.get_raw('https://a.example.com/') do |response|
            streaming << response
            finish.pop
            response
          end
        end

        expect(Timeout.timeout(5) { streaming.pop }).to eq(:response)
        Timeout.timeout(5) do
          %w[b c d e].each { |origin| pool.get_raw("https://#{origin}.example.com/") }
        end
        expect(oldest_idle).to have_received(:close).once
        expect(active).not_to have_received(:close)

        finish << true
        expect(Timeout.timeout(5) { worker.value }).to eq(:response)
      ensure
        worker&.kill
        worker&.join
      end
    end

    it 'serializes requests on a shared session and waits for room for another origin' do
      shared = stub_session
      other = stub_session
      allow(session_class).to receive(:new).and_return(shared, other)
      allow(shared).to receive(:get_raw).and_yield
      allow(other).to receive(:get_raw).and_return(:other_response)
      finish_first = Queue.new
      finish_second = Queue.new

      described_class.open(limit: 1) do |pool|
        first = Thread.new { pool.get_raw('https://a.example.com/first') { finish_first.pop } }
        wait_until_blocked(first)
        second = Thread.new { pool.get_raw('https://a.example.com/second') { finish_second.pop } }
        wait_until_blocked(second)
        competing = Thread.new { pool.get_raw('https://b.example.com/') }
        wait_until_blocked(competing)
        expect(shared).not_to have_received(:get_raw).with('https://a.example.com/second', {})
        expect(session_class).to have_received(:new).once

        finish_first << true
        Timeout.timeout(5) { first.value }
        expect(shared).not_to have_received(:close)
        expect(session_class).to have_received(:new).once

        finish_second << true
        Timeout.timeout(5) { second.value }
        expect(Timeout.timeout(5) { competing.value }).to eq(:other_response)
        expect(shared).to have_received(:get_raw).with('https://a.example.com/second', {}).once
        expect(shared).to have_received(:close).once
      ensure
        [first, second, competing].compact.each do |thread|
          thread.kill
          thread.join
        end
      end
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
