# frozen_string_literal: true

require 'fileutils'
require 'tempfile'

module CircleCI
  module CLI
    module Command
      class ArtifactsCommand
        class Download
          MAX_REDIRECTS = 5

          def initialize(destination, headers, sessions)
            @destination = destination
            @headers = headers
            @sessions = sessions
            @mutex = Mutex.new
          end

          # The directory walk and tempfile creation below are fast and rely on Dir.fchdir,
          # which mutates the process-wide working directory, so they stay serialized across
          # worker threads under @mutex. The slow part - the HTTPS GET and read_body - runs
          # outside the mutex against the already-open tempfile handle, so multiple downloads
          # can overlap their network transfers.
          def save(artifact)
            parts = path_components(artifact)
            directory, file = open_destination(parts)
            committed = false
            begin
              stream(URI(artifact.url), file)
              file.close
              @mutex.synchronize { Dir.fchdir(directory.fileno) { File.rename(file.path, parts.last) } }
              committed = true
            ensure
              cleanup_tempfile(directory, file) unless committed
              directory.close
            end
          rescue Thor::Error, SystemCallError, IOError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError,
                 URI::Error, Net::ProtocolError => e
            raise Thor::Error, "Could not download #{artifact_label(artifact)}: #{Printer.escape_controls(e.message)}"
          end

          private

          def artifact_label(artifact)
            Printer.escape_controls("#{artifact.path} (job #{artifact.job_id}, execution #{artifact.execution})")
          end

          def open_destination(parts)
            @mutex.synchronize do
              directory = open_leaf_directory(parts[0...-1])
              begin
                [directory, create_tempfile(directory)]
              rescue StandardError
                directory.close
                raise
              end
            end
          end

          # Each step below resolves a single path component relative to the already-opened
          # parent directory (via fchdir), so a symlink swapped in after a parent was
          # validated cannot redirect the next mkdir/open onto a different path. The leaf
          # directory's descriptor is duplicated so it survives the enclosing File.open blocks
          # closing their own descriptors as they unwind.
          def open_leaf_directory(parts)
            File.open(destination_root, File::RDONLY) { |root| descend(root, parts) }
          end

          def descend(parent, parts)
            return parent.dup if parts.empty?

            Dir.fchdir(parent.fileno) do
              create_directory(parts.first)
              File.open(parts.first, File::RDONLY | File::NOFOLLOW) { |child| descend(child, parts[1..]) }
            end
          end

          def create_tempfile(directory)
            Dir.fchdir(directory.fileno) { Tempfile.create('.artifact-', '.', binmode: true) }
          end

          def cleanup_tempfile(directory, file)
            file.close unless file.closed?
            @mutex.synchronize { Dir.fchdir(directory.fileno) { File.delete(file.path) } }
          end

          def path_components(artifact)
            parts = artifact.path.split('/', -1)
            unless RunLookup::UUID.match?(artifact.job_id) && artifact.execution.is_a?(Integer) &&
                   artifact.execution >= 0 && !parts.empty? && parts.all? { safe_component?(_1) }
              raise Thor::Error, 'Unsafe artifact path.'
            end

            [artifact.job_id, artifact.execution.to_s, *parts]
          end

          def safe_component?(part)
            !part.empty? && !%w[. ..].include?(part) && !part.match?(/[[:cntrl:]\\:]/)
          end

          def destination_root
            @destination_root ||= begin
              FileUtils.mkdir_p(@destination)
              File.realpath(@destination)
            end
          end

          def create_directory(name)
            Dir.mkdir(name)
          rescue Errno::EEXIST
            raise Thor::Error, 'Artifact directory is a symlink or a file.' unless File.lstat(name).directory?
          end

          def stream(uri, file, redirects = MAX_REDIRECTS)
            raise Thor::Error, 'Invalid HTTPS artifact URL.' unless uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo

            location = nil
            @sessions.get_raw(uri.to_s, headers_for(uri)) do |response|
              location = read_response(response, file)
            end
            return unless location

            raise Thor::Error, 'Too many artifact redirects.' if redirects.zero?

            stream(uri.merge(location), file, redirects - 1)
          end

          def read_response(response, file)
            case response
            when Net::HTTPOK
              response.ignore_eof = false
              response.read_body(file)
              nil
            when Net::HTTPRedirection
              response['location'] || raise(Thor::Error, 'Artifact redirect has no location.')
            else
              raise Thor::Error, "HTTP #{response.code}"
            end
          end

          def headers_for(uri)
            host = uri.host.downcase
            return {} unless uri.port == 443
            return @headers if host == 'circleci.com' || host.end_with?('.circleci.com', '.circle-artifacts.com')

            {}
          end
        end
      end
    end
  end
end
