# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class BuildRepository
        EVICTED_REFRESH_INTERVAL = 5

        def initialize(username, reponame, branch: nil, user: nil)
          @username = username
          @user = user
          @reponame = reponame
          @branch = branch
          @mutex = Mutex.new
          @builds = fetch_builds
          @recent_build_numbers = @builds.to_set(&:build_number)
          @build_numbers_shown = @builds.select(&:finished?).to_set(&:build_number)
          @evicted_refresh_tick = 0
          @evicted_build_cache = {}
        end

        def update
          response = fetch_builds

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

        def refresh_evicted_builds(&fetch_detail)
          fetch_detail ||= Response::Build.method(:get)
          @mutex.synchronize do
            @evicted_refresh_tick += 1
            details = @builds.select { |build| evicted_pending?(build) }.to_h do |build|
              [build.build_number, refresh_evicted_build(build.build_number, fetch_detail)]
            end
            @evicted_build_cache.keep_if { |number, _| details.key?(number) }
            @builds.map! { |build| details[build.build_number] || build }
            details
          end
        end

        def build_for(build_number, recent_only: false)
          @mutex.synchronize do
            find_build(build_number) if !recent_only || @recent_build_numbers.include?(build_number)
          end
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

        def evicted_pending?(build)
          !@recent_build_numbers.include?(build.build_number) && pending?(build)
        end

        # Mirrors BuildWatcher's 5-poll backoff so unwatched evicted builds aren't re-fetched every tick.
        def refresh_evicted_build(number, fetch_detail)
          cache = (@evicted_build_cache[number] ||= { due: 0, detail: nil })
          return cache[:detail] if @evicted_refresh_tick < cache[:due]

          detail = fetch_detail.call(@username, @reponame, number)
          cache[:due] = detail ? @evicted_refresh_tick + EVICTED_REFRESH_INTERVAL : @evicted_refresh_tick
          cache[:detail] = detail if detail
          cache[:detail]
        end

        def find_build(build_number)
          @builds.find { |build| build.build_number == build_number }
        end

        def fetch_builds
          return Response::Build.branch(@username, @reponame, @branch) if @branch

          Response::Build.all(@username, @reponame)
        end
      end
    end
  end
end
