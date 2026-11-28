# Architecture

## Command dispatch

The [gem executable](../exe/circleci-cli) starts the Thor
[runner](../lib/circleci/cli.rb). The runner declares the commands and options,
fills in Git project and branch defaults for commands that use them, and
dispatches to a command class. [BaseCommand](../lib/circleci/cli/command/base_command.rb)
provides shared helpers for token setup, project selection, and build numbers.

## API calls and terminal output

Start with [BuildsCommand](../lib/circleci/cli/command/builds_command.rb) for a
short example. It resolves the project and branch, then calls
[Response::Build](../lib/circleci/cli/response/build.rb) for recent builds.
The response class calls the `circleci` gem, checks for API errors through
[`Response.body!`](../lib/circleci/cli/response.rb), and wraps the returned
records as build objects. The command passes those objects to
[BuildPrinter](../lib/circleci/cli/printer/build_printer.rb) for terminal output.

[`run`](../lib/circleci/cli/command/run_command.rb) uses the
[HTTP client](../lib/circleci/cli/networking/http_client.rb) directly to query
the CircleCI v3 API and builds a table from the run's workflows and jobs.

## Live build watching

[WatchCommand](../lib/circleci/cli/command/watch_command.rb) listens for Pusher
events that trigger a build list refresh.
[BuildRepository](../lib/circleci/cli/command/watch_command/build_repository.rb)
tracks recent builds and which results have been shown.
[BuildWatcher](../lib/circleci/cli/command/watch_command/build_watcher.rb)
polls build details and action output for the active build, delegating to
[ActionLogTracker](../lib/circleci/cli/command/watch_command/action_log_tracker.rb)
for action-output streaming and failure-log retention, and to
[StepNotifier](../lib/circleci/cli/command/watch_command/step_notifier.rb) for
step-transition terminal output.

## Artifact downloads

[ArtifactsCommand](../lib/circleci/cli/command/artifacts_command.rb) lists and
downloads a run's artifacts through the CircleCI v3 API, using the same
[RunLookup](../lib/circleci/cli/command/run_lookup.rb) workflow/job lookup as
`run`. Listing artifacts and downloading them both fan out across jobs through
[RunRequestPool](../lib/circleci/cli/command/run_command/run_request_pool.rb),
which runs up to `LIMIT` worker threads over a shared queue. Downloads share a
[SessionPool](../lib/circleci/cli/networking/http_client.rb) that keeps one
HTTPS connection alive per origin so redirected artifact URLs on the same host
don't reconnect for every file.
[Download](../lib/circleci/cli/command/artifacts_command/download.rb) streams
each artifact into a temp file and only renames it into place once the
download finishes, walking the destination path through already-opened
directory descriptors so a symlink swapped in mid-download can't redirect the
write.

## Workflow approvals

[ApproveCommand](../lib/circleci/cli/command/approve_command.rb) also builds
on `RunLookup` to list a run's pending `approval`-type jobs grouped by
workflow. With `--job NAME`, it looks up that job's `approval_request_id` and
POSTs to the CircleCI workflow approve endpoint through the same `Session`
used for GET requests.

## Where to start with tests

For command dispatch and Git defaults, see the
[runner specs](../spec/circleci/cli/cli_spec.rb). For the build-listing example
above, see the [builds command specs](../spec/circleci/cli/command/builds_command_spec.rb).
For the concurrent fetch and download path, see the
[artifacts command specs](../spec/circleci/cli/command/artifacts_command_spec.rb).
For listing and approving pending jobs, see the
[approve command specs](../spec/circleci/cli/command/approve_command_spec.rb).
The [contributing guide](../CONTRIBUTING.md) covers development setup and checks.
