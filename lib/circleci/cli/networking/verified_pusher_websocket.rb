# frozen_string_literal: true

require 'pusher-client'
require 'timeout'

module CircleCI
  module CLI
    module Networking
      class VerifiedPusherWebSocket < PusherClient::PusherWebSocket
        CONNECT_TIMEOUT = 10

        # The parent initializer opens the connection without hostname verification.
        def initialize(url, cert_file: nil, logger: PusherClient.logger) # rubocop:disable Lint/MissingSuper
          @logger = logger
          @hs = WebSocket::Handshake::Client.new(url: url)
          @frame = WebSocket::Frame::Incoming::Server.new(version: @hs.version)
          @cert_file = cert_file || CA_FILE
        end

        def connect
          Timeout.timeout(CONNECT_TIMEOUT, nil, 'Pusher WebSocket handshake timed out') do
            connect_tls
            handshake
          end
        end

        private

        def connect_tls
          context = OpenSSL::SSL::SSLContext.new
          context.set_params(ca_file: @cert_file, verify_mode: OpenSSL::SSL::VERIFY_PEER, verify_hostname: true)
          @socket = TCPSocket.new(@hs.host, @hs.port || 443)
          tls = OpenSSL::SSL::SSLSocket.new(@socket, context)
          tls.sync_close = true
          @socket = tls
          tls.hostname = @hs.host
          tls.connect
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
