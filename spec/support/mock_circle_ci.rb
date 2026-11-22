# frozen_string_literal: true

shared_context 'mock circle ci response' do
  let(:circleci_response_project_name) { 'user/project_name_from_api' }
  let(:account_hash) { { 'name' => 'account name' } }
  let(:build_hash) do
    {
      'username' => circleci_response_project_name.split('/').first,
      'reponame' => circleci_response_project_name.split('/').last,
      'status' => 'success',
      'build_num' => 1234,
      'branch' => 'master',
      'author_name' => circleci_response_project_name.split('/').first,
      'subject' => 'Commit',
      'build_time_millis' => 1000,
      'start_time' => 100_000,
      'steps' => [
        {
          'status' => 'success',
          'actions' => [{ 'type' => 'build', 'name' => 'Build', 'status' => 'success', 'run_time_millis' => 1000 }]
        },
        {
          'status' => 'success',
          'actions' => [{ 'type' => 'test', 'name' => 'Test', 'status' => 'success', 'run_time_millis' => 1000 }]
        }
      ]
    }
  end

  let(:project_hash) do
    {
      'username' => 'unhappychoice',
      'reponame' => 'default_reponame_from_api',
      'vcs_url' => 'https://github.com/unhappychoice/default_reponame_from_api'
    }
  end

  let(:http_status) { '200' }
  let(:builds_body) { [build_hash] }
  let(:projects_body) do
    [
      project_hash,
      { 'username' => 'org', 'reponame' => 'repo', 'vcs_url' => 'https://bitbucket.org/org/repo' },
      { 'username' => 'org', 'reponame' => 'unknown-provider' }
    ]
  end

  def circleci_response(body)
    CircleCi::Response.new(double('HTTP response', code: http_status, body: JSON.generate(body)))
  end

  before do
    allow(CircleCi::User).to receive_message_chain(:me, :body) { account_hash }
    allow_any_instance_of(CircleCi::Project).to receive(:recent_builds) { circleci_response(builds_body) }
    allow_any_instance_of(CircleCi::Project).to receive(:recent_builds_branch).and_return(circleci_response(builds_body))
    allow_any_instance_of(CircleCi::Build).to receive(:get) { circleci_response(build_hash) }
    allow_any_instance_of(CircleCi::Build).to receive(:retry).and_return(circleci_response(build_hash))
    allow_any_instance_of(CircleCi::Build).to receive(:cancel).and_return(circleci_response(build_hash))
    allow_any_instance_of(CircleCi::Projects).to receive(:get).and_return(circleci_response(projects_body))
  end
end

RSpec.configure do |config|
  config.include_context 'mock circle ci response'
end
