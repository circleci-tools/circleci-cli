# frozen_string_literal: true

require 'yaml'

RSpec.describe 'Coverage workflow' do
  it 'reads the Codecov upload token from the GitHub Actions secret' do
    workflow_path = File.expand_path('../.github/workflows/test.yml', __dir__)
    workflow = YAML.safe_load_file(workflow_path)
    steps = workflow.fetch('jobs').fetch('test').fetch('steps')
    upload = steps.find { |step| step['uses'].to_s.start_with?('codecov/codecov-action@') }

    expect(upload).to include('with' => include('token' => '${{ secrets.CODECOV_TOKEN }}'))
  end
end
