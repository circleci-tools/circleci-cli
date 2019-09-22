# frozen_string_literal: true

shared_context 'mock io' do
  let(:circle_ci_token) { 'circle-ci-token' }
  let(:project_name) { 'unhappychoice/default_project_name_from_io' }
  let(:build_number) { 1234 }

  before do
    ObjectSpace.each_object(Class).select { |klass| klass < Circler::BaseCommand }.each do |klass|
      allow(klass).to receive(:ask).with('Circle CI token ? :') { circle_ci_token }
      allow(klass).to receive(:ask).with('Input user-name/project-name :') { project_name }
      allow(klass).to receive(:ask).with('Input build number') { build_number }
      allow(klass).to receive(:reponame) { nil }
    end
  end
end

shared_examples_for 'a command asks project name' do
  let(:expected_project_name_output) do
    <<~EXPECTED
      +---------------+---------------------------+
      |                 \e[0;32;49mProjects\e[0m                  |
      +---------------+---------------------------+
      | User name     | Repository name           |
      +---------------+---------------------------+
      | unhappychoice | default_reponame_from_api |
      +---------------+---------------------------+
    EXPECTED
  end

  it 'should show project list' do
    allow(Launchy).to receive(:open)
    expect(Circler::BrowseCommand).to receive(:say).with(expected_project_name_output.strip)
    Circler::BrowseCommand.run(options)
  end
end

RSpec.configure do |config|
  config.include_context 'mock io', type: :command
end
