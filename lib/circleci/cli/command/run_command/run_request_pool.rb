# frozen_string_literal: true

module CircleCI
  module CLI
    module Command
      class RunRequestPool
        LIMIT = 4

        def self.fetch(items, &fetch_item)
          pending = Queue.new(items.each_with_index).tap(&:close)
          results = Array.new(items.size)
          workers = Array.new([items.size, LIMIT].min) do
            Thread.new { fetch_pending(pending, results, &fetch_item) }
          end
          workers.each(&:join)
          results.each { |result| raise result if result.is_a?(StandardError) }
        end

        def self.fetch_pending(pending, results)
          Networking::HTTPClient::Session.open(max_retries: 1) do |session|
            while (entry = pending.pop)
              item, index = entry
              results[index] = yield(session, item)
            end
          rescue StandardError => e
            pending.clear
            results[index] = e
          end
        end
        private_class_method :fetch_pending
      end
    end
  end
end
