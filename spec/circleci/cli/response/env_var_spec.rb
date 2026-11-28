# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Response::EnvVar do
  let(:project) { instance_double(CircleCi::Project) }

  before { allow(CircleCi::Project).to receive(:new).with('octocat', 'hello-world', 'github').and_return(project) }

  describe '.all' do
    subject(:env_vars) { described_class.all('octocat', 'hello-world') }

    let(:body) { [{ 'name' => 'FOO', 'value' => 'xxxx1234' }, { 'name' => 'BAR', 'value' => 'xxxx5678' }] }

    before { allow(project).to receive(:envvar).and_return(double(body: body, success?: true)) }

    it 'returns the masked environment variables' do
      expect(env_vars.map(&:name)).to eq(%w[FOO BAR])
      expect(env_vars.map(&:value)).to eq(%w[xxxx1234 xxxx5678])
    end
  end

  describe '.set' do
    subject(:env_var) { described_class.set('octocat', 'hello-world', 'FOO', 'bar') }

    let(:body) { { 'name' => 'FOO', 'value' => 'xxxx1234' } }
    let(:response) { double(body: body, success?: true) }

    before { allow(project).to receive(:add_envvar).with(name: 'FOO', value: 'bar').and_return(response) }

    it 'returns the created environment variable' do
      expect(env_var.name).to eq('FOO')
      expect(env_var.value).to eq('xxxx1234')
    end
  end

  describe '.delete' do
    subject(:result) { described_class.delete('octocat', 'hello-world', 'FOO') }

    let(:response) { double(body: { 'message' => 'ok' }, success?: true) }

    before { allow(project).to receive(:delete_envvar).with('FOO').and_return(response) }

    it 'returns the API confirmation' do
      expect(result).to eq('message' => 'ok')
    end
  end

  context 'when the API request fails' do
    subject(:env_vars) { described_class.all('octocat', 'hello-world') }

    let(:response) { double(body: { 'message' => 'Not Found' }, success?: false, code: '404') }

    before { allow(project).to receive(:envvar).and_return(response) }

    it 'raises an error with the API detail' do
      expect { env_vars }.to raise_error(Thor::Error, 'CircleCI API error (HTTP 404): Not Found')
    end
  end
end
