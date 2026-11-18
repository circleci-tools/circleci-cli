# frozen_string_literal: true

require 'uri'

module CircleCI
  module CLI
    module Response
      class Build
        class << self
          def all(username, reponame)
            response = CircleCi::Project.new(username, reponame, 'github').recent_builds
            Response.body!(response).map { |b| Build.new(b) }
          end

          def failed(username, reponame)
            response = CircleCi::Project.new(username, reponame, 'github').recent_builds(filter: 'failed')
            Response.body!(response).map { |b| Build.new(b) }
          end

          def branch(username, reponame, branch)
            encoded_branch = URI.encode_uri_component(branch)
            response = CircleCi::Project.new(username, reponame, 'github').recent_builds_branch(encoded_branch)
            Response.body!(response).map { |b| Build.new(b) }
          end

          def get(username, reponame, number)
            response = CircleCi::Build.new(username, reponame, 'github', number).get
            Build.new(Response.body!(response))
          end

          def retry(username, reponame, number)
            response = CircleCi::Build.new(username, reponame, 'github', number).retry
            Build.new(Response.body!(response))
          end

          def cancel(username, reponame, number)
            response = CircleCi::Build.new(username, reponame, 'github', number).cancel
            Build.new(Response.body!(response))
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
          %w[running queued].include?(status)
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
            status,
            branch,
            author_name,
            (@hash['subject'] || '').slice(0..60),
            format_time(@hash['build_time_millis']),
            start_time
          ]
        end

        def steps
          (@hash['steps'] || []).map { |step| Step.new(step['actions'].first['type'], step) }
        end

        private

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
