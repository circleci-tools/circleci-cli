# frozen_string_literal: true

require 'circleci/cli/command/run_lookup'

module CircleCI
  module CLI
    module Command
      class ArtifactsCommand < RunLookup
        Artifact = Data.define(:workflow, :job, :job_id, :execution, :path, :url)

        def self.run(run_id, download: nil, destination: nil)
          raise Thor::Error, 'Run ID must be a UUID.' unless UUID.match?(run_id)
          unless [download, destination].all?(&:nil?) || [download, destination].all? { !_1.to_s.empty? }
            raise Thor::Error, 'Provide both --download PATH and --destination DIRECTORY.'
          end

          new(setup_token).artifacts(run_id, download:, destination:)
        end

        def artifacts(run_id, download:, destination:)
          entries = collect(run_jobs(run_id))
          return render(entries) unless download

          matches = entries.select { File.fnmatch?(download, _1.path, File::FNM_PATHNAME | File::FNM_DOTMATCH) }
          return 'No artifacts matched the download filter.' if matches.empty?

          download_matches(matches, destination)
          "Downloaded #{matches.size} #{matches.size == 1 ? 'artifact' : 'artifacts'}.\n#{render(matches)}"
        end

        private

        def download_matches(matches, destination)
          Networking::HTTPClient::SessionPool.open do |sessions|
            downloader = Download.new(destination, @headers, sessions)
            RunRequestPool.fetch(matches) { |_session, artifact| downloader.save(artifact) }
          end
        end

        def collect(groups)
          job_list = groups.flat_map do |workflow, jobs|
            jobs.reject { _1.fetch('attributes')['type'] == 'approval' }.map { [workflow, _1] }
          end
          results = RunRequestPool.fetch(job_list) do |session, (workflow, job)|
            job_artifacts(session, workflow, job)
          end
          results.flatten(1)
        end

        def job_artifacts(session, workflow, job)
          id = job.fetch('id')
          name = job.fetch('attributes').fetch('name')
          get(session, "jobs/#{id}/artifacts").fetch('data').map do |entry|
            fields = entry.fetch('attributes')
            Artifact.new(workflow, name, id, *fields.fetch_values('execution', 'path', 'url'))
          end
        end

        def render(entries)
          return 'No artifacts found.' if entries.empty?

          rows = entries.map do |artifact|
            [artifact.workflow, artifact.job, artifact.job_id, artifact.execution, artifact.path].map do |cell|
              Printer.escape_controls(cell)
            end
          end
          Terminal::Table.new(headings: ['Workflow', 'Job', 'Job ID', 'Execution', 'Path'], rows:).to_s
        end
      end
    end
  end
end

require 'circleci/cli/command/artifacts_command/artifact_stream'
require 'circleci/cli/command/artifacts_command/download'
