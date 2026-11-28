# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class RunRequestPool
        LIMIT = 4

        def self.fetch(items, raise_errors: true, &fetch_item)
          pending = Queue.new(items.each_with_index).tap(&:close)
          results = Array.new(items.size)
          workers = Array.new([items.size, LIMIT].min) do
            Thread.new { fetch_pending(pending, results, raise_errors:, &fetch_item) }
          end
          workers.each(&:join)
          results.each { |result| raise result if result.is_a?(StandardError) } if raise_errors
          results
        end

        def self.fetch_pending(pending, results, raise_errors:, &fetch_item)
          Networking::HTTPClient::Session.open(max_retries: 1) do |session|
            while (entry = pending.pop)
              item, index = entry
              results[index] = fetch_result(session, item, raise_errors:, &fetch_item)
            end
          rescue StandardError => e
            pending.clear
            results[index] = e
          end
        end

        def self.fetch_result(session, item, raise_errors:)
          yield(session, item)
        rescue StandardError => e
          raise if raise_errors

          e
        end
        private_class_method :fetch_pending, :fetch_result
      end
    end
  end
end
