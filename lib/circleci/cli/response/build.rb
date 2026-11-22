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
            build = get(username, reponame, number)
            rerun_job(build.workflow_id, build.workflow_job_id)
          end

          def cancel(username, reponame, number)
            response = CircleCi::Build.new(username, reponame, 'github', number).cancel
            Build.new(Response.body!(response))
          end

          private

          def rerun_job(workflow_id, job_id)
            unless valid_id?(workflow_id) && valid_id?(job_id)
              raise Thor::Error, 'The selected build is missing its workflow or job ID.'
            end

            body = Response.body!(rerun_request(workflow_id).post(jobs: [job_id]))
            rerun_id = body['workflow_id'] if body.is_a?(Hash)
            return rerun_id if valid_id?(rerun_id)

            raise Thor::Error, 'CircleCI rerun response did not include a workflow ID.'
          end

          def rerun_request(workflow_id)
            config = CircleCi.config.dup
            config.version = 'v2'
            CircleCi.request(config, "/workflow/#{URI.encode_uri_component(workflow_id)}/rerun")
          end

          def valid_id?(id)
            id.is_a?(String) && !id.strip.empty?
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

        def workflow_id
          @hash.dig('workflows', 'workflow_id')
        end

        def workflow_job_id
          @hash.dig('workflows', 'job_id')
        end

        def running?
          %w[running queued].include?(status)
        end

        def finished?
          lifecycle = @hash['lifecycle']
          return lifecycle == 'finished' unless lifecycle.nil?

          %w[success canceled failed no_tests].include?(status)
        end

        def channel_name
          "private-#{username}@#{reponame}@#{build_number}@vcs-github@0"
        end

        def project_name
          "#{username}/#{reponame}"
        end

        def subject
          @hash['subject']
        end

        def build_time_millis
          @hash['build_time_millis']
        end

        def steps
          (@hash['steps'] || []).map { |step| Step.new(step) }
        end
      end
    end
  end
end
