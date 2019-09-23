# circleci-cli

Notice: This gem is renamed from `circler` to `circleci-cli` on 2019/09/22

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
  circleci-cli browse          # open circle ci website
  circleci-cli build           # show build description
  circleci-cli builds          # list builds
  circleci-cli help [COMMAND]  # describe available commands or one specific command
  circleci-cli projects        # list projects
  circleci-cli retry           # retry a build
  circleci-cli version         # show gem version
  circleci-cli watch           # watch a build in real time

Options:
  -p user_name/project   # specify repository
  -b branch              # specify branch name
  -n build_number        # specify build number
  -l last                # get or retry last failed build
  -v verbose             # show all the logs if applied to watch command
```

### Project argument

Project argument will be automatically selected in your directory initialized with git.

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
