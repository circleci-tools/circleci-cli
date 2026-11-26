# frozen_string_literal: true

require 'fileutils'
require 'tempfile'

module CircleCI
  module CLI
    module Command
      class ArtifactsCommand
        class Download
          # The directory walk and tempfile creation below are fast and rely on Dir.fchdir,
          # which mutates the process-wide working directory, so they stay serialized across
          # worker threads under @mutex. The slow part - the HTTPS GET and read_body - runs
          # outside the mutex against the already-open tempfile handle, so multiple downloads
          # can overlap their network transfers.
          class DestinationDirectory
            def initialize(destination)
              @destination = destination
              @mutex = Mutex.new
            end

            def store(parts)
              directory, file = open_destination(parts)
              commit(directory, file, parts.last) { yield file }
            end

            private

            def commit(directory, file, name)
              committed = false
              begin
                yield
                file.close
                rename(directory, file, name)
                committed = true
              ensure
                cleanup_tempfile(directory, file) unless committed
                directory.close
              end
            end

            def rename(directory, file, name)
              @mutex.synchronize { Dir.fchdir(directory.fileno) { File.rename(file.path, name) } }
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
          end

          def initialize(destination, headers, sessions)
            @directory = DestinationDirectory.new(destination)
            @stream = ArtifactStream.new(headers, sessions)
          end

          def save(artifact)
            parts = path_components(artifact)
            @directory.store(parts) { |file| @stream.fetch(artifact.url, file) }
          rescue Thor::Error, SystemCallError, IOError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError,
                 URI::Error, Net::ProtocolError => e
            raise Thor::Error, "Could not download #{artifact_label(artifact)}: #{Printer.escape_controls(e.message)}"
          end

          private

          def artifact_label(artifact)
            Printer.escape_controls("#{artifact.path} (job #{artifact.job_id}, execution #{artifact.execution})")
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
        end
      end
    end
  end
end
