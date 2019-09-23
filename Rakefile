# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'github_changelog_generator/task'

RSpec::Core::RakeTask.new(:spec)

task default: :spec

GitHubChangelogGenerator::RakeTask.new :changelog do |config|
  config.user = 'unhappychoice'
  config.project = 'circleci-cli'
  config.since_tag = '0.1.0'
  # config.future_release = '2.2.0'
end
