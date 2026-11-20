# frozen_string_literal: true

require 'pusher-client'

module CircleCI
  module CLI
    module Networking
      class VerifiedPusherWebSocket < PusherClient::PusherWebSocket
        # The parent initializer opens the connection without hostname verification.
        def initialize(url, cert_file: nil, logger: PusherClient.logger) # rubocop:disable Lint/MissingSuper
          @logger = logger
          @hs = WebSocket::Handshake::Client.new(url: url)
          @frame = WebSocket::Frame::Incoming::Server.new(version: @hs.version)
          @socket = connect_tls(cert_file || CA_FILE)
          handshake
        rescue StandardError
          @socket&.close
          raise
        end

        private

        def connect_tls(cert_file)
          context = OpenSSL::SSL::SSLContext.new
          context.set_params(ca_file: cert_file, verify_mode: OpenSSL::SSL::VERIFY_PEER, verify_hostname: true)
          tcp = TCPSocket.new(@hs.host, @hs.port || 443)
          tls = OpenSSL::SSL::SSLSocket.new(tcp, context)
          tls.sync_close = true
          tls.hostname = @hs.host
          tls.connect
        rescue StandardError
          tcp&.close
          raise
        end

        def handshake
          @socket.write(@hs.to_s)
          @socket.flush

          until @hs.finished?
            byte = @socket.getc
            raise EOFError, 'WebSocket closed during handshake' unless byte

            @hs << byte
          end
          raise @hs.error.to_s unless @hs.valid?

          @handshaked = true
        end
      end
    end
  end
end
