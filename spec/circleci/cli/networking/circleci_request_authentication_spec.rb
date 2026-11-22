# frozen_string_literal: true

require 'spec_helper'

describe 'CircleCI API v1.1 authentication' do
  let(:token) { 'dummy-api-token' }
  let(:config) { CircleCi::Config.new }
  let(:http) { instance_double(Net::HTTP) }
  let(:response) { instance_double(Net::HTTPOK, code: '200', body: '{}') }

  before do
    allow(CircleCi).to receive(:config).and_return(config)
    allow(ENV).to receive(:fetch).with('CIRCLE_CI_TOKEN', nil).and_return(token)
    CircleCI::CLI::Command::BaseCommand.setup_token
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:start).and_yield(http)
  end

  it 'authenticates a GET and preserves the ordinary query parameters' do
    expect(http).to receive(:request) do |request, _body|
      expect(request.method).to eq('GET')
      expect(request.path).to eq('/api/v1.1/project/github/owner/repo?filter=failed&limit=10')
      expect(request['Circle-Token']).to eq(token)
      response
    end

    CircleCi.request(config, '/project/github/owner/repo', filter: 'failed', limit: 10).get
  end

  it 'authenticates a POST with a token-free request target' do
    expect(http).to receive(:request) do |request, _body|
      expect(request.method).to eq('POST')
      expect(request.path).to eq('/api/v1.1/project/github/owner/repo/42/cancel')
      expect(request['Circle-Token']).to eq(token)
      expect(request.body).to eq('{}')
      response
    end

    CircleCi.request(config, '/project/github/owner/repo/42/cancel').post
  end
end
