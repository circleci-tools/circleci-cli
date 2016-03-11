# Circler

[![Circle CI](https://circleci.com/gh/unhappychoice/circler.svg?style=svg)](https://circleci.com/gh/unhappychoice/circler)

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

#### watch
watch build in real time

```sh
$ circle watch

# Options:
# p, [--project=user/project]
```

#### projects

list all the projects you can see.

```sh
$ circle projects
```

#### builds

list specific projects' builds.

```sh
$ circle builds

# Options:
# p, [--project=user/project]
# b, [--branch=some-branch]
```

#### build

show specific build description.

```sh
$ circle build

# Options:
# p, [--project=user/project]
# n, [--build=build-number]
```

#### browse

open Circle CI website

```sh
$ circle browse

# Options:
# p, [--project=user/project]
# n, [--build=build-number]
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/unhappychoice/circler.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
