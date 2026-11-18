# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class BuildRepository
        def initialize(username, reponame, branch: nil, user: nil)
          @username = username
          @user = user
          @reponame = reponame
          @branch = branch
          @mutex = Mutex.new
          @builds = Response::Build.all(@username, @reponame)
          @recent_build_numbers = @builds.to_set(&:build_number)
          @build_numbers_shown = @builds.select(&:finished?).to_set(&:build_number)
        end

        def update
          response = if @branch
                       Response::Build.branch(@username, @reponame, @branch)
                     else
                       Response::Build.all(@username, @reponame)
                     end

          @mutex.synchronize { retain_builds(response) }
        end

        def mark_as_shown(build_number)
          @mutex.synchronize do
            @watched_build_number = nil if @watched_build_number == build_number
            if @recent_build_numbers.include?(build_number)
              @build_numbers_shown.add(build_number)
            else
              @builds.reject! { |build| build.build_number == build_number }
              @build_numbers_shown.delete(build_number)
            end
          end
        end

        def watch(build_number)
          @mutex.synchronize do
            build = find_build(build_number)
            next unless build && !build.finished?

            @watched_build_number = build_number
            build
          end
        end

        def builds_to_show
          @mutex.synchronize { @builds.select { |build| pending?(build) }.sort_by(&:build_number) }
        end

        def build_for(build_number)
          @mutex.synchronize { find_build(build_number) }
        end

        private

        def retain_builds(response)
          @recent_build_numbers = response.to_set(&:build_number)
          @builds = (response + @builds.select { |build| retain?(build) }).uniq(&:build_number)
          @build_numbers_shown.keep_if { |number| @recent_build_numbers.include?(number) }
          @builds
        end

        def retain?(build)
          build.build_number == @watched_build_number || pending?(build)
        end

        def pending?(build)
          build.build_number != @watched_build_number &&
            !@build_numbers_shown.include?(build.build_number) &&
            (@branch.nil? || build.branch == @branch) &&
            (@user.nil? || build.user == @user)
        end

        def find_build(build_number)
          @builds.find { |build| build.build_number == build_number }
        end
      end
    end
  end
end
