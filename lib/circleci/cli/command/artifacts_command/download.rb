# frozen_string_literal: true

require 'fileutils'
require 'tempfile'

module CircleCI
  module CLI
    module Command
      class ArtifactsCommand
        class Download
          MAX_REDIRECTS = 5

          def initialize(destination, headers)
            @destination = destination
            @headers = headers
          end

          def save(artifact)
            parts = path_components(artifact)
            directory = parts[0...-1].reduce(destination_root) { |parent, part| create_directory(parent, part) }
            write_artifact(directory, parts.last, artifact.url)
          rescue Thor::Error, SystemCallError, IOError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError,
                 URI::Error, Net::ProtocolError => e
            raise Thor::Error, "Could not download #{artifact_label(artifact)}: #{Printer.escape_controls(e.message)}"
          end

          private

          def artifact_label(artifact)
            Printer.escape_controls("#{artifact.path} (job #{artifact.job_id}, execution #{artifact.execution})")
          end

          def write_artifact(directory, name, url)
            Tempfile.create('.artifact-', directory, binmode: true) do |file|
              stream(URI(url), file)
              file.close
              File.rename(file.path, File.join(directory, name))
            end
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

          def create_directory(parent, part)
            path = File.join(parent, part)
            begin
              Dir.mkdir(path)
            rescue Errno::EEXIST
              raise Thor::Error, 'Artifact directory is a symlink or a file.' unless File.lstat(path).directory?
            end
            path
          end

          def stream(uri, file, redirects = MAX_REDIRECTS)
            raise Thor::Error, 'Invalid HTTPS artifact URL.' unless uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo

            location = nil
            Networking::HTTPClient.get_raw(uri.to_s, headers_for(uri)) do |response|
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
