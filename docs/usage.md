# Command reference

Run `circleci-cli help` to list commands or `circleci-cli help COMMAND` to see
the options for one command.

| Command | Description | Options |
| --- | --- | --- |
| `projects` | List projects available to your account. | `--no-pretty` |
| `builds` | List recent builds for a project. | `-p, --project OWNER/REPO`, `-b, --branch BRANCH`, `-a, --all`, `--no-pretty` |
| `build` | Show the steps and available failure logs for a build. | `-p, --project OWNER/REPO`, `-n, --build NUMBER`, `-l, --last`, `--no-pretty` |
| `browse` | Open the project or build in your browser. | `-p, --project OWNER/REPO`, `-n, --build NUMBER` |
| `cancel` | Cancel a build. | `-p, --project OWNER/REPO`, `-n, --build NUMBER` |
| `retry` | Retry a build. | `-p, --project OWNER/REPO`, `-n, --build NUMBER`, `-l, --last` |
| `run RUN_ID` | Show the workflows and jobs for a CircleCI run. Use the run UUID. | `--failed-tests` |
| `artifacts RUN_ID` | List or download artifacts from a run. Use the run UUID. | `--download PATH`, `--destination DIRECTORY` |
| `watch` | Watch builds in real time. | `-p, --project OWNER/REPO`, `-b, --branch BRANCH`, `-a, --all`, `-u, --user USER`, `-v, --verbose` |
| `env list` | List a project's environment variables (values are masked by the API). | `-p, --project OWNER/REPO`, `--no-pretty` |
| `env set NAME [VALUE]` | Set a project's environment variable. Omit `VALUE` for secure input. | `-p, --project OWNER/REPO` |
| `env delete NAME` | Delete a project's environment variable. | `-p, --project OWNER/REPO` |
| `version` | Show the installed gem version. | |

## Project and branch selection

Commands with `--project` default to the GitHub `origin` remote in your local
checkout. If no GitHub project is detected, the CLI lists available projects
and prompts for an `OWNER/REPO`.

For `builds` and `watch`, the CLI uses the current Git branch when available.
Use `--branch` to select a different branch or `--all` to include every branch
even if you supplied `--branch`. Without a branch filter, both commands
include builds across branches.

## Build selection and output

- `build`, `cancel`, and `retry` prompt for a positive build number if you omit
  `--build`. For `build` and `retry`, `--last` selects the most recent failed
  build for the project instead of prompting.
- `browse` opens the project page when you omit `--build`.
- `projects`, `builds`, and `build` use formatted output by default. Pass
  `--no-pretty` for compact output.
- `watch --user USER` filters by user login. Use `--verbose` to also show
  available logs from successful build actions.
- `run --failed-tests` adds failures grouped by workflow and job when failed
  jobs have uploaded test results with `store_test_results`.
- `artifacts RUN_ID` lists every artifact's workflow, job name, job UUID,
  execution index, and path. Provide both `--download PATH` and
  `--destination DIRECTORY` together to download artifacts whose path matches
  the `PATH` glob into `DIRECTORY` instead of listing them. Downloads require a
  POSIX platform with Ruby support for `Dir.fchdir`.
- `env list` uses formatted output by default; pass `--no-pretty` for compact
  `NAME=VALUE` output. The CircleCI API returns masked values for `env list`.

## Setting environment variables

Omit the value to keep it out of shell history and process arguments. In a
terminal, the command prompts for the value without echoing what you type.

```sh
circleci-cli env set API_KEY -p owner/repo
```

With piped or redirected standard input, the command reads the value through
EOF and preserves trailing newlines. Set `CIRCLE_CI_TOKEN` and supply the
project when running without a terminal.

```sh
circleci-cli env set API_KEY -p owner/repo < /path/to/secret-file
```

The command confirms the variable name and project. A positional value is
also supported, but can appear in shell history and process listings.

## Authentication

Set `CIRCLE_CI_TOKEN` to your CircleCI API token. When it is unset, commands
that need the CircleCI API prompt for the token without echoing it.
`browse` only needs the token when it has to list projects for selection.
