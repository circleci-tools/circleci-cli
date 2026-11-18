# Contributing

## Set up your development environment

Fork this repository on GitHub, clone your fork, and create a branch for your
change. Use the Ruby version in [`.ruby-version`](.ruby-version) and the Bundler
version listed under `BUNDLED WITH` in [`Gemfile.lock`](Gemfile.lock). From the
repository root, install the development dependencies:

```sh
bin/setup
```

## Run the checks

Run the same lint and test commands used by the GitHub Actions test workflow:

```sh
bundle exec rubocop lib
bundle exec rspec
```

## Open a pull request

Push your branch to your fork and open a pull request against the upstream
repository. Describe what changed, why it changed, and which checks you ran.
Link the related issue if there is one.
