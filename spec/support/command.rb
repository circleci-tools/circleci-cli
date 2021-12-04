# frozen_string_literal: true

shared_examples_for 'a command asks project name' do
  let(:expected_project_name_output) do
    <<~EXPECTED
      +-------------------------------------------+
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
    expect(CircleCI::CLI::Command::BrowseCommand).to receive(:say).with(expected_project_name_output.strip)
    CircleCI::CLI::Command::BrowseCommand.run(options)
  end
end
