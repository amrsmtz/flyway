require "net/http"

module Inaturalist
  # Thin wrapper around the iNaturalist API v1 (no key needed).
  class Client
    BASE_URL = "https://api.inaturalist.org/v1/".freeze
    # iNaturalist asks for about one request per second.
    MIN_INTERVAL = 1.0
    PAGE_SIZE = 200
    # Aves.
    BIRDS_TAXON_ID = 3

    class Error < StandardError; end
    class RateLimited < Error; end
    class Unavailable < Error; end
    class RequestError < Error; end

    # Bird observations in the given places, in ascending id order starting
    # after id_above. Paging by id avoids the API's 10,000-result ceiling.
    def bird_observations(place_ids:, id_above:, **filters)
      params = { taxon_id: BIRDS_TAXON_ID, place_id: place_ids.join(","), per_page: PAGE_SIZE,
                 order_by: "id", order: "asc", id_above: id_above, **filters }
      get("observations", params).fetch("results")
    end

    private

    def get(path, params)
      uri = URI.join(BASE_URL, path)
      uri.query = URI.encode_www_form(params)
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Flyway bird migration demo"

      throttle
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60) do |http|
        http.request(request)
      end
      parse(response, path)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => e
      raise Unavailable, "#{path}: #{e.class}"
    end

    def parse(response, path)
      status = response.code.to_i
      raise RateLimited, "#{path}: too many requests" if status == 429
      raise Unavailable, "#{path}: HTTP #{status}" if status >= 500
      raise RequestError, "#{path}: HTTP #{status} #{response.body.to_s.first(200)}" if status >= 400

      JSON.parse(response.body)
    rescue JSON::ParserError
      raise Unavailable, "#{path}: response is not JSON"
    end

    def throttle
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      wait = @last_request_at ? MIN_INTERVAL - (now - @last_request_at) : 0
      sleep(wait) if wait.positive?
      @last_request_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
