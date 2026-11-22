# frozen_string_literal: true

require 'bundler'
require 'open3'
require 'rbconfig'
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
  it 'accepts the default OpenSSL gem when it is loaded before Bundler' do
    release_ruby = File.read(File.expand_path('../.ruby-version', __dir__)).strip
    skip "Release uses Ruby #{release_ruby}" unless RUBY_VERSION == release_ruby

    script = <<~RUBY_CODE
      default_spec = Gem::Specification.default_stubs.find { |spec| spec.name == 'openssl' }
      loaded_version = Gem.loaded_specs.fetch('openssl').version
      abort 'OpenSSL version differs from the Ruby default' unless loaded_version == default_spec.version
    RUBY_CODE
    output, status = Bundler.with_original_env do
      Open3.capture2e({ 'BUNDLE_FROZEN' => 'true' }, RbConfig.ruby, '-ropenssl', '-rbundler/setup', '-e', script)
    end

    expect(status).to be_success, output
  end

  it 'loads the gem-release bump command through Bundler' do
    output, status = Bundler.with_original_env do
      Open3.capture2e({ 'BUNDLE_FROZEN' => 'true' }, 'bundle', 'exec', 'gem', 'bump', '--help')
    end

    expect(status).to be_success, output
    expect(output).to include('Usage: gem bump', '--version VERSION')
  end
end
