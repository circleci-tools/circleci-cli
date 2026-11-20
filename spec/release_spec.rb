# frozen_string_literal: true

require 'bundler'
require 'open3'

RSpec.describe 'Release bundle' do
  it 'loads the gem-release bump command through Bundler' do
    output, status = Bundler.with_original_env do
      Open3.capture2e({ 'BUNDLE_FROZEN' => 'true' }, 'bundle', 'exec', 'gem', 'bump', '--help')
    end

    expect(status).to be_success, output
    expect(output).to include('Usage: gem bump', '--version VERSION')
  end
end
