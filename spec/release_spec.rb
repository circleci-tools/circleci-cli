# frozen_string_literal: true

require 'bundler'
require 'open3'
require 'yaml'

RSpec.describe 'Release workflow' do
  it 'pins each publishing action to a full commit SHA' do
    workflow = YAML.safe_load_file(File.expand_path('../.github/workflows/release.yaml', __dir__))
    actions = workflow.fetch('jobs').fetch('push').fetch('steps').filter_map { |step| step['uses'] }

    expect(actions).not_to be_empty
    expect(actions).to all(match(%r{\A[^/@]+/[^@]+@[0-9a-f]{40}\z}))
  end
end

RSpec.describe 'Release bundle' do
  it 'loads the gem-release bump command through Bundler' do
    output, status = Bundler.with_original_env do
      Open3.capture2e({ 'BUNDLE_FROZEN' => 'true' }, 'bundle', 'exec', 'gem', 'bump', '--help')
    end

    expect(status).to be_success, output
    expect(output).to include('Usage: gem bump', '--version VERSION')
  end
end
