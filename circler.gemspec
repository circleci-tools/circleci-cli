# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'circler/version'

def production_dependency(spec)
  spec.add_dependency 'pusher-client', '~> 0.6.2'
  spec.add_dependency 'thor', '~> 0.19.4'
  spec.add_dependency 'faraday', '~> 0.12.0'
  spec.add_dependency 'launchy', '~> 2.4.3'
  spec.add_dependency 'circleci', '~> 2.0.2'
  spec.add_dependency 'rugged', '~> 0.26.0'
  spec.add_dependency 'terminal-table', '~> 1.8.0'
  spec.add_dependency 'highline', '~> 1.7.8'
  spec.add_dependency 'colorize', '~> 0.8.1'
  spec.add_dependency 'terminal-notifier', '~> 2.0.0'
end

def development_dependency(spec)
  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rubocop'
end

def project_files
  `git ls-files -z`
    .split("\x0")
    .reject { |f| f.match(%r{^(test|spec|features)/}) }
end

Gem::Specification.new do |spec|
  spec.name          = 'circler'
  spec.version       = Circler::VERSION
  spec.authors       = ['unhappychoice']
  spec.email         = ['unhappychoice@gmail.com']

  spec.summary       = 'CLI tool for CircleCI'
  spec.description   = 'A command line tool for CircleCI'
  spec.homepage      = 'https://github.com/unhappychoice/circler'
  spec.license       = 'MIT'
  spec.files         = project_files
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  production_dependency spec
  development_dependency spec
end
