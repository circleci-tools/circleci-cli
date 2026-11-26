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
            stream(parse_artifact_uri(url), file)
          end

          private

          def parse_artifact_uri(url)
            raise URI::InvalidURIError unless well_formed_uri?(url)

            URI(url)
          rescue URI::Error
            raise Thor::Error, 'Invalid artifact URL.'
          end

          def stream(uri, file, redirects = MAX_REDIRECTS)
            raise Thor::Error, 'Invalid HTTPS artifact URL.' unless uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo

            location = nil
            @sessions.get_raw(uri.to_s, headers_for(uri)) do |response|
              location = read_response(response, file)
            end
            return unless location

            raise Thor::Error, 'Too many artifact redirects.' if redirects.zero?

            stream(merge_redirect_uri(uri, location), file, redirects - 1)
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

          def read_response(response, file)
            response.ignore_eof = false
            case response
            when Net::HTTPOK
              response.read_body(file)
              nil
            else
              non_ok_response(response)
            end
          end

          def non_ok_response(response)
            drain(response)
            raise Thor::Error, "HTTP #{response.code}" unless response.is_a?(Net::HTTPRedirection)

            response['location'] || raise(Thor::Error, 'Artifact redirect has no location.')
          end

          # Net::HTTP leaves the body on the socket until it's read; a response left unread
          # here would corrupt the next request on the same pooled connection.
          def drain(response)
            response.body
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
