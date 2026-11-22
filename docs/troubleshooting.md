# FAQ and troubleshooting

## Why does the CLI ask for a project?

The CLI looks for a GitHub project in the local checkout's `origin` remote.
If you're outside a checkout or `origin` points elsewhere, pass the GitHub
repository explicitly:

```sh
circleci-cli builds -p user/project
```

Use the `owner/repo` format without a URL. Run `circleci-cli projects` to find
the owner and repository names.

## Why is a recent build missing from the list?

Inside a Git checkout, `builds` defaults to the current branch. Use
`--branch` to select a different branch or `--all` to search across branches:

```sh
circleci-cli builds -p user/project --all
```

## Why does `build --last` say there is no failed build?

`--last` looks for the latest failed build. To inspect a specific build, use
the value in the `Number` column from `builds`:

```sh
circleci-cli build -p user/project -n 42
```

## Why does `run` reject my run number?

`run` expects a CircleCI run UUID. Use the `id` from the API, as shown in the
[run example](../README.md#show-every-job-in-a-run).
