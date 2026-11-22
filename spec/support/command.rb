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

  it 'suggests only followed GitHub projects and opens the selected repository' do
    project = project_hash.values_at('username', 'reponame').join('/')
    allow(CircleCI::CLI::Command::BrowseCommand).to receive(:ask).with('Input user-name/project-name :').and_return(project)
    url = "https://circleci.com/gh/#{project}"
    url += "/#{options.build}" if options.build
    expect(Launchy).to receive(:open).with(url)
    expect { CircleCI::CLI::Command::BrowseCommand.run(options) }.to output(expected_project_name_output).to_stdout
  end
end
