# Getting started

## Install the CLI

Use Ruby 3.3 or newer and install the gem from RubyGems:

```sh
gem install circleci-cli
circleci-cli version
```

Artifact downloads require a POSIX platform with Ruby support for `Dir.fchdir`.
Artifact listing works without this filesystem support.

## Find your project

Have your CircleCI API token ready and list the GitHub projects you follow in
CircleCI:

```sh
circleci-cli projects
```

The CLI uses `CIRCLE_CI_TOKEN` if set. Otherwise, it prompts for the token
without echoing it. Combine the `User name` and `Repository name` columns as
`user/project` for the next steps.

## Find and inspect a build

Replace `user/project` with the GitHub project you selected. With `--all`, the
CLI lists builds across branches even when you run it from a Git checkout:

```sh
circleci-cli builds -p user/project --all
```

To narrow the list to one branch, use `-b` in place of `--all`:

```sh
circleci-cli builds -p user/project -b main
```

Choose a value from the `Number` column and pass it to `build`. The output
shows the build steps and includes logs for failed actions when available:

```sh
circleci-cli build -p user/project -n 42
```

See [FAQ and troubleshooting](troubleshooting.md) for help with project
selection, missing builds, and run IDs.
