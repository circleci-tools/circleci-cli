# circleci-cli
[![All Contributors](https://img.shields.io/badge/all_contributors-3-orange.svg?style=flat-square)](#contributors-)
[![Gem Version](https://badge.fury.io/rb/circleci-cli.svg)](https://badge.fury.io/rb/circleci-cli)
[![codecov](https://codecov.io/gh/circleci-tools/circleci-cli/branch/master/graph/badge.svg)](https://codecov.io/gh/circleci-tools/circleci-cli)
[![Libraries.io dependency status for GitHub repo](https://img.shields.io/librariesio/github/circleci-tools/circleci-cli.svg)](https://libraries.io/github/circleci-tools/circleci-cli)
![](http://ruby-gem-downloads-badge.herokuapp.com/circleci-cli?type=total)
![GitHub](https://img.shields.io/github/license/circleci-tools/circleci-cli.svg)

circleci-cli is a CLI tool for [Circle CI](https://circleci.com).

![sample.gif](https://github.com/circleci-tools/circleci-cli/raw/master/movie/rec.gif)

## Installation

```sh
$ gem install circleci-cli
```

set the `CIRCLE_CI_TOKEN` environment variable. (optional)

```sh
export CIRCLE_CI_TOKEN=your-circle-ci-token
```

## Quick start

In a local checkout of a GitHub project that builds on CircleCI, switch to the branch you want to inspect and run:

```sh
circleci-cli builds
```

Enter your CircleCI API token when prompted if `CIRCLE_CI_TOKEN` is unset.
The command identifies the project from the GitHub `origin` remote and shows a table of recent builds on the current branch, including their build numbers and statuses.

See the [getting started guide](docs/getting-started.md) to find a project and
inspect a build from any directory.

## Usage

See the [command reference](docs/usage.md) for command options, Git defaults,
and token configuration. Run `circleci-cli help COMMAND` to see the options
for an individual command.

### Examples

#### Show every job in a run

With `CIRCLE_CI_TOKEN` set, list your recent runs with the CircleCI API and
copy the `id` next to the run number you want:

```sh
curl -fsS -G 'https://circleci.com/api/v3/runs' \
  -H "Authorization: Bearer ${CIRCLE_CI_TOKEN}" \
  --data-urlencode 'filter[user_id]=me' | jq -r '.data[] | [.attributes.number, .id] | @tsv'
circleci-cli run 123e4567-e89b-12d3-a456-426614174000
```

On projects supported by `build`, use the displayed job number to inspect its
steps, for example `circleci-cli build -p user/project -n 42`.

Use `circleci-cli run RUN_ID --failed-tests` to include failed tests from jobs
that failed, grouped by workflow and job. Jobs must upload test results with
`store_test_results` for test details to appear. Each reported failure is
shown, including repeats from parallel executions.

#### Watch your project
```
$ circleci-cli watch
```

#### Watch your project and show all of the build log
```
$ circleci-cli watch -v
```

#### Show last failed build
```
$ circleci-cli build --last
```

#### Retry last failed build
```
$ circleci-cli retry --last
```

#### Open CircleCI webpage for current project
```
$ circleci-cli browse
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/circleci-tools/circleci-cli.
See the [contributing guide](CONTRIBUTING.md) for development setup and checks.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

## Contributors ✨

Thanks goes to these wonderful people ([emoji key](https://allcontributors.org/docs/en/emoji-key)):

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tr>
    <td align="center"><a href="http://blog.unhappychoice.com"><img src="https://avatars3.githubusercontent.com/u/5608948?v=4" width="100px;" alt=""/><br /><sub><b>Yuji Ueki</b></sub></a><br /><a href="https://github.com/unhappychoice/circleci-cli/commits?author=unhappychoice" title="Code">💻</a></td>
    <td align="center"><a href="https://mattbrictson.com/"><img src="https://avatars0.githubusercontent.com/u/189693?v=4" width="100px;" alt=""/><br /><sub><b>Matt Brictson</b></sub></a><br /><a href="https://github.com/unhappychoice/circleci-cli/commits?author=mattbrictson" title="Code">💻</a> <a href="https://github.com/unhappychoice/circleci-cli/commits?author=mattbrictson" title="Tests">⚠️</a></td>
    <td align="center"><a href="http://fzf.me"><img src="https://avatars0.githubusercontent.com/u/1462357?v=4" width="100px;" alt=""/><br /><sub><b>Fletcher Fowler</b></sub></a><br /><a href="https://github.com/unhappychoice/circleci-cli/issues?q=author%3Afzf" title="Bug reports">🐛</a> <a href="#ideas-fzf" title="Ideas, Planning, & Feedback">🤔</a> <a href="https://github.com/unhappychoice/circleci-cli/commits?author=fzf" title="Code">💻</a></td>
    <td align="center"><a href="https://datadoghq.com"><img src="https://avatars3.githubusercontent.com/u/583503?v=4" width="100px;" alt=""/><br /><sub><b>Marco Costa</b></sub></a><br /><a href="#ideas-marcotc" title="Ideas, Planning, & Feedback">🤔</a> <a href="https://github.com/unhappychoice/circleci-cli/commits?author=marcotc" title="Code">💻</a></td>
  </tr>
</table>

<!-- markdownlint-enable -->
<!-- prettier-ignore-end -->
<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind welcome!

## Author

[@unhappychoice](https://unhappychoice.com)
