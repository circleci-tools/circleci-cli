# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'circleci/cli/version'

def production_dependency(spec)
  spec.add_dependency 'circleci', '~> 2.0.2'
  spec.add_dependency 'faraday', '>= 0.14', '< 1.4'
  spec.add_dependency 'highline', '>= 1.7.8', '< 2.1.0'
  spec.add_dependency 'launchy', '>= 2.4.3', '< 2.6.0'
  spec.add_dependency 'pusher-client', '~> 0.6.2'
  spec.add_dependency 'rugged', '>= 0.26', '< 1.2'
  spec.add_dependency 'terminal-notifier', '~> 2.0.0'
  spec.add_dependency 'terminal-table', '>= 1.8', '< 3.1'
  spec.add_dependency 'thor', '>= 0.20', '< 1.2'
end

def development_dependency(spec)
  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'codecov'
  spec.add_development_dependency 'github_changelog_generator'
  spec.add_development_dependency 'guard'
  spec.add_development_dependency 'guard-rspec'
  spec.add_development_dependency 'guard-rubocop'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'simplecov'
end

def project_files
  `git ls-files -z`
    .split("\x0")
    .reject { |f| f.match(%r{^(test|spec|features)/}) }
end

Gem::Specification.new do |spec|
  spec.name          = 'circleci-cli'
  spec.version       = CircleCI::CLI::VERSION
  spec.required_ruby_version = '>= 2.5'
  spec.authors       = ['unhappychoice']
  spec.email         = ['unhappychoice@gmail.com']

  spec.summary       = 'CLI tool for CircleCI'
  spec.description   = 'A command line tool for CircleCI'
  spec.homepage      = 'https://github.com/unhappychoice/circleci-cli'
  spec.license       = 'MIT'
  spec.files         = project_files
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  production_dependency spec
  development_dependency spec
end
