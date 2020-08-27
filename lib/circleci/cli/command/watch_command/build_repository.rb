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
          @builds = Response::Build.all(@username, @reponame)
          @build_numbers_shown = @builds.select(&:finished?).map(&:build_number)
        end

        def update
          response = if @branch
                       Response::Build.branch(@username, @reponame, @branch)
                     else
                       Response::Build.all(@username, @reponame)
                     end

          @builds = (response + @builds).uniq(&:build_number)
        end

        def mark_as_shown(build_number)
          @build_numbers_shown = (@build_numbers_shown + [build_number]).uniq
        end

        def builds_to_show
          @builds
            .reject { |build| @build_numbers_shown.include?(build.build_number) }
            .select { |build| @branch.nil? || build.branch.to_s == @branch.to_s }
            .select { |build| @user.nil? || build.user.to_s == @user.to_s }
            .sort_by(&:build_number)
        end

        def build_for(build_number)
          @builds.find { |build| build.build_number == build_number }
        end
      end
    end
  end
end
