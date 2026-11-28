# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class ArtifactsCommand
        class ArtifactStream
          MAX_REDIRECTS = 5

          def initialize(headers, sessions)
            @headers = headers
            @sessions = sessions
          end

          def fetch(url, file)
            uri = parse_artifact_uri(url)
            validate_https_uri(uri)
            stream(uri, file)
          end

          private

          def parse_artifact_uri(url)
            raise URI::InvalidURIError unless well_formed_uri?(url)

            URI(url)
          rescue URI::Error
            raise Thor::Error, 'Invalid artifact URL.'
          end

          def stream(uri, file, redirects = MAX_REDIRECTS)
            target = nil
            @sessions.get_raw(uri.to_s, headers_for(uri)) do |response|
              target = read_response(response, file, uri, redirects)
            end
            stream(target, file, redirects - 1) if target
          end

          def validate_https_uri(uri)
            raise Thor::Error, 'Invalid HTTPS artifact URL.' unless uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo
          end

          def merge_redirect_uri(uri, location)
            raise URI::InvalidURIError unless well_formed_uri?(location)

            uri.merge(location)
          rescue URI::Error
            raise Thor::Error, 'Invalid artifact redirect URL.'
          end

          def well_formed_uri?(value)
            !value.match?(/[[:space:]]|[[:cntrl:]]/)
          end

          def read_response(response, file, uri, redirects)
            response.ignore_eof = false
            case response
            when Net::HTTPOK
              response.read_body(file)
              nil
            else
              redirect_target(response, uri, redirects)
            end
          end

          # Raising inside the request block closes the socket when a body is abandoned.
          def redirect_target(response, uri, redirects)
            raise Thor::Error, "HTTP #{response.code}" unless response.is_a?(Net::HTTPRedirection)

            location = response['location'] || raise(Thor::Error, 'Artifact redirect has no location.')
            raise Thor::Error, 'Too many artifact redirects.' if redirects.zero?

            target = merge_redirect_uri(uri, location)
            validate_https_uri(target)
            response.read_body { nil }
            target
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
