# Circler

[![Gem Version](https://badge.fury.io/rb/circler.svg)](https://badge.fury.io/rb/circler)
[![Circle CI](https://circleci.com/gh/unhappychoice/Circler.svg?style=shield)](https://circleci.com/gh/unhappychoice/Circler)
[![Code Climate](https://codeclimate.com/github/unhappychoice/Circler/badges/gpa.svg)](https://codeclimate.com/github/unhappychoice/Circler)
[![Libraries.io dependency status for GitHub repo](https://img.shields.io/librariesio/github/unhappychoice/Circler.svg)](https://libraries.io/github/unhappychoice/Circler)
![](http://ruby-gem-downloads-badge.herokuapp.com/circler?type=total)
![GitHub](https://img.shields.io/github/license/unhappychoice/Circler.svg)

Circler is a CLI tool for [Circle CI](https://circleci.com).

![sample.gif](https://github.com/unhappychoice/circler/raw/master/movie/rec.gif)

## Installation

```sh
$ gem install circler
```

set the `CIRCLE_CI_TOKEN` environment variable. (optional)

```sh
export CIRCLE_CI_TOKEN=your-circle-ci-token
```

## Usage
```
Commands:
  circle browse          # open circle ci website
  circle build           # show build description
  circle builds          # list builds
  circle help [COMMAND]  # describe available commands or one specific command
  circle projects        # list projects
  circle retry           # retry a build
  circle version         # show gem version
  circle watch           # watch a build in real time

Options:
  -p user_name/project   # specify repository
  -b branch              # specify branch name
  -n build_number        # specify build number
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/unhappychoice/circler.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
