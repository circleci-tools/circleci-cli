# frozen_string_literal: true

shared_context 'mock rugged response' do
  let(:mock_rugged_repository) { double('Rugged::Repository', remotes: mock_rugged_remotes, head: mock_rugged_head) }
  let(:mock_rugged_remotes) { [double('Rugged::Remote', name: 'origin', url: rugged_response_remote_url)] }

  let(:mock_rugged_head) do
    instance_double(Rugged::Reference, name: rugged_response_branch_name, branch?: rugged_response_is_branch)
  end

  let(:rugged_response_remote_url) { 'git@github.com:user/local-repository-from-rugged.git' }
  let(:rugged_response_branch_name) { 'local_branch_name_from_rugged' }
  let(:rugged_response_is_branch) { rugged_response_branch_name }

  before do
    allow(Rugged::Repository).to receive(:new).with('.').and_return(mock_rugged_repository)
  end
end

RSpec.configure do |config|
  config.include_context 'mock rugged response'
end
