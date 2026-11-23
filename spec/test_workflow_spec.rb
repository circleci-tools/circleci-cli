# frozen_string_literal: true

require 'yaml'

RSpec.describe 'Test workflow' do
  it 'limits the GitHub token to read-only repository contents' do
    workflow = YAML.safe_load_file(File.expand_path('../.github/workflows/test.yml', __dir__))
    permissions = workflow.fetch('permissions')

    expect(permissions).to eq('contents' => 'read')
    expect(workflow.fetch('jobs').values.map { |job| job.fetch('permissions', permissions) }).to all(eq(permissions))
  end
end
