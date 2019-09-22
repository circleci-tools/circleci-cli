# frozen_string_literal: true

module Circler
  class Build
    class << self
      def all(username, reponame)
        CircleCi::Project.new(username, reponame, 'github').recent_builds
                         .body
                         .map { |b| Build.new(b) }
      end

      def branch(username, reponame, branch)
        CircleCi::Project.new(username, reponame, 'github').recent_builds_branch(branch)
                         .body
                         .map { |b| Build.new(b) }
      end

      def get(username, reponame, number)
        Build.new(CircleCi::Build.new(username, reponame, 'github', number).get.body)
      end

      def retry(username, reponame, number)
        Build.new(CircleCi::Build.new(username, reponame, 'github', number).retry.body)
      end

      def cancel(username, reponame, number)
        Build.new(CircleCi::Build.new(username, reponame, 'github', number).cancel.body)
      end
    end

    def initialize(hash)
      @hash = hash
    end

    def username
      @hash['username']
    end

    def reponame
      @hash['reponame']
    end

    def status
      @hash['status']
    end

    def build_number
      @hash['build_num']
    end

    def running?
      status == 'running'
    end

    def channel_name
      "private-#{username}@#{reponame}@#{build_number}@vcs-github@0"
    end

    def project_name
      "#{username}/#{reponame}"
    end

    def information
      [
        @hash['build_num'],
        colorize_by_status(@hash['status'], @hash['status']),
        colorize_by_status(@hash['branch'], @hash['status']),
        @hash['author_name'],
        (@hash['subject'] || '').slice(0..60),
        format_time(@hash['build_time_millis']),
        @hash['start_time']
      ]
    end

    def steps
      hash = @hash['steps'].group_by { |s| s['actions'].first['type'] }
      hash.flat_map { |type, value| value.map { |v| Step.new(type, v) } }
    end

    private

    def colorize_by_status(string, status)
      case status
      when 'success', 'fixed' then string.green
      when 'canceled' then string.yellow
      when 'failed' then string.red
      when 'no_tests', 'not_run' then string.light_black
      else string
      end
    end

    def format_time(time)
      return '' unless time

      minute = format('%02d', time / 1000 / 60)
      second = format('%02d', (time / 1000) % 60)
      "#{minute}:#{second}"
    end
  end
end
