# frozen_string_literal: true

module CircleCI
  module CLI
    module Response
      class Build
        class << self
          def all(username, reponame)
            CircleCi::Project.new(username, reponame, 'github').recent_builds
                             .body
                             .map { |b| Build.new(b) }
          end

          def failed(username, reponame)
            CircleCi::Project.new(username, reponame, 'github').recent_builds(filter: 'failed')
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

        attr_reader :username, :build_number, :reponame, :branch, :status, :author_name, :start_time,
                    :user, :workflow_name, :workflow_job_name

        def initialize(hash) # rubocop:disable Metrics/MethodLength
          @hash = hash
          @username = hash['username']
          @build_number = hash['build_num']
          @reponame = hash['reponame']
          @branch = hash['branch']
          @status = hash['status']
          @author_name = hash['author_name']
          @start_time = hash['start_time']
          @user = hash.dig('user', 'login')
          @workflow_name = hash.dig('workflows', 'workflow_name')
          @workflow_job_name = hash.dig('workflows', 'job_name')
        end

        def running?
          status == 'running' || status || 'queued'
        end

        def finished?
          %w[success canceled failed no_tests].include?(status)
        end

        def channel_name
          "private-#{username}@#{reponame}@#{build_number}@vcs-github@0"
        end

        def project_name
          "#{username}/#{reponame}"
        end

        def information
          [
            build_number,
            colorize_by_status(status, status),
            colorize_by_status(branch, status),
            author_name,
            (@hash['subject'] || '').slice(0..60),
            format_time(@hash['build_time_millis']),
            start_time
          ]
        end

        def steps
          hash = @hash['steps'].group_by { |s| s['actions'].first['type'] }
          hash.flat_map { |type, value| value.map { |v| Step.new(type, v) } }
        end

        private

        def colorize_by_status(string, status)
          case status
          when 'success', 'fixed' then Printer.colorize_green(string)
          when 'canceled' then Printer.colorize_yellow(string)
          when 'failed' then Printer.colorize_red(string)
          when 'no_tests', 'not_run' then Printer.colorize_light_black(string)
          else string
          end
        end

        def format_time(time)
          return '' unless time

          minute = format('%<time>02d', time: time / 1000 / 60)
          second = format('%<time>02d', time: (time / 1000) % 60)
          "#{minute}:#{second}"
        end
      end
    end
  end
end
