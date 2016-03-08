module Circler
  class Action
    attr_reader :name, :status, :run_time_millis
    def initialize(hash)
      @hash = hash
      @name = hash['name']
      @status = hash['status']
      @run_time_millis = hash['run_time_millis']
    end

    def log
      request(@hash['output_url'])
        .map{ |r|
          r['message']
            .gsub(/\r\n/, "\n")
            .gsub(/\e\[A\r\e\[2K/, '')
            .scan(/.{1,120}/)
            .join("\n")
        }
        .join("\n")
    end

    def failed?
      @status == 'timedout' || @status == 'failed'
    end

    private

    def request(url)
      JSON.parse(Faraday.new(url).get.body)
    end
  end
end
