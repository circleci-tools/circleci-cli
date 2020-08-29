# circleci-cli
[![All Contributors](https://img.shields.io/badge/all_contributors-3-orange.svg?style=flat-square)](#contributors-)
[![Gem Version](https://badge.fury.io/rb/circleci-cli.svg)](https://badge.fury.io/rb/circleci-cli)
[![Circle CI](https://circleci.com/gh/unhappychoice/circleci-cli.svg?style=shield)](https://circleci.com/gh/unhappychoice/circleci-cli)
[![Code Climate](https://codeclimate.com/github/unhappychoice/circleci-cli/badges/gpa.svg)](https://codeclimate.com/github/unhappychoice/circleci-cli)
[![codecov](https://codecov.io/gh/unhappychoice/circleci-cli/branch/master/graph/badge.svg)](https://codecov.io/gh/unhappychoice/circleci-cli)
[![Libraries.io dependency status for GitHub repo](https://img.shields.io/librariesio/github/unhappychoice/circleci-cli.svg)](https://libraries.io/github/unhappychoice/circleci-cli)
![](http://ruby-gem-downloads-badge.herokuapp.com/circleci-cli?type=total)
![GitHub](https://img.shields.io/github/license/unhappychoice/circleci-cli.svg)

circleci-cli is a CLI tool for [Circle CI](https://circleci.com).

![sample.gif](https://github.com/unhappychoice/circler/raw/master/movie/rec.gif)

## Installation

```sh
$ gem install circleci-cli
```

set the `CIRCLE_CI_TOKEN` environment variable. (optional)

```sh
export CIRCLE_CI_TOKEN=your-circle-ci-token
```

## Usage
```
Commands:
  circleci-cli browse               # Open CircleCI website
  circleci-cli build                # Show the build result
  circleci-cli builds               # List builds
  circleci-cli cancel               # Cancel a build
  circleci-cli help [COMMAND]       # Describe available commands or one specific command
  circleci-cli projects             # List projects
  circleci-cli retry                # Retry a build
  circleci-cli version              # Show gem version
  circleci-cli watch                # Watch builds in real time

Options:
  -p user_name/project              # Specify repository
                                    # Default to the Git remote of current directory

  -b branch                         # Specify branch name
                                    # Default to the current Git branch

  -a, --all, --no-all               # Ignore the branch option and stop being filtered by the branch
                                    # Default to false

  -n build_number                   # Specify build number.
  -l last                           # Get or retry last failed build.
  -v verbose                        # Show all the logs if applied to watch command.

  --pretty=true/false, --no-pretty  # Make outputs pretty or not
                                    # Default to true
```

### Examples

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

Bug reports and pull requests are welcome on GitHub at https://github.com/unhappychoice/circleci-cli.

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
