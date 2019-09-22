# frozen_string_literal: true

shared_context 'mock circle ci response' do
  let(:account_hash) { { 'name' => 'account name' } }
  let(:build_hash) do
    {
      'username' => 'unhappychoice',
      'reponame' => 'unhappychoice/default_reponame_from_api',
      'status' => 'success',
      'build_number' => 1234,
      'branch' => 'master',
      'author_name' => 'unhappychoice',
      'subject' => 'Commit',
      'build_time_millis' => 1000,
      'start_time' => 100_000
    }
  end

  let(:project_hash) { { 'username' => 'unhappychoice', 'reponame' => 'default_reponame_from_api' } }

  before do
    allow(CircleCi::User).to receive_message_chain(:me, :body) { account_hash }
    allow_any_instance_of(CircleCi::Build).to receive_message_chain(:recent_builds, :body) { [build_hash] }
    allow_any_instance_of(CircleCi::Build).to receive_message_chain(:recent_builds_branch, :body) { [build_hash] }
    allow_any_instance_of(CircleCi::Build).to receive_message_chain(:get, :body) { build_hash }
    allow_any_instance_of(CircleCi::Build).to receive_message_chain(:retry, :body) { build_hash }
    allow_any_instance_of(CircleCi::Build).to receive_message_chain(:cancel, :body) { build_hash }
    allow_any_instance_of(CircleCi::Projects).to receive_message_chain(:get, :body) { [project_hash] }
  end
end

RSpec.configure do |config|
  config.include_context 'mock circle ci response'
end
