require "net/http"

module Ebird
  # Thin wrapper around the eBird API 2.0. It only knows how to make one
  # request safely; throttling and retries belong to the ingestion layer.
  class Client
    BASE_URL = "https://api.ebird.org/v2/".freeze
    DEFAULT_TIMEOUT = 20
    # eBird allows bursts of 25 requests per 5 seconds; stay well below.
    MIN_INTERVAL = 0.25

    class Error < StandardError; end
    # 429: the hourly or burst quota is exhausted.
    class RateLimited < Error; end
    # 5xx or timeout: eBird could not answer; safe to retry later.
    class Unavailable < Error; end
    # Other 4xx: the request itself is wrong; retrying will not help.
    class RequestError < Error; end

    # Remaining calls in the hourly window, read from the last response.
    attr_reader :remaining_quota

    def initialize(api_key: Rails.application.credentials.dig(:ebird, :api_key))
      raise ArgumentError, "eBird API key is missing from credentials" if api_key.blank?

      @api_key = api_key
    end

    def taxonomy_versions
      get("ref/taxonomy/versions")
    end

    # The whole taxonomy in one response (about 18,000 taxa), hence the
    # longer timeout.
    def taxonomy
      get("ref/taxonomy/ebird", params: { fmt: "json" }, timeout: 90)
    end

    # Sub-regions of a region, e.g. the counties ("subnational2") of CA-QC.
    def sub_regions(parent_code, type: "subnational2")
      get("ref/region/list/#{type}/#{parent_code}")
    end

    # Name, centre and bounding box of a region.
    def region_info(region_code)
      get("ref/region/info/#{region_code}")
    end

    # Every hotspot of a region, with its position and all-time totals.
    def hotspots(region_code)
      get("ref/hotspot/#{region_code}", params: { fmt: "json" }, timeout: 90)
    end

    # What eBird says happened in a region on a day: numbers of checklists,
    # contributors and species.
    def region_stats(region_code, date)
      get("product/stats/#{region_code}/#{date_path(date)}", record: true)
    end

    # One observation per species reported in a region on a day (the latest
    # one). Provisional records are included so that review status is visible.
    def historic_observations(region_code, date)
      get("data/obs/#{region_code}/historic/#{date_path(date)}", record: true,
          params: { detail: "full", includeProvisional: true })
    end

    # Checklists submitted for a region and day, 200 at most.
    def checklist_feed(region_code, date)
      get("product/lists/#{region_code}/#{date_path(date)}", params: { maxResults: 200 })
    end

    # A full checklist: effort fields and every species reported.
    def checklist(submission_id)
      get("product/checklist/view/#{submission_id}", record: true)
    end

    private

    def date_path(date)
      date.to_date.strftime("%Y/%-m/%-d")
    end

    def get(path, params: {}, timeout: DEFAULT_TIMEOUT, record: false)
      uri = URI.join(BASE_URL, path)
      uri.query = URI.encode_www_form(params) if params.any?

      request = Net::HTTP::Get.new(uri)
      request["X-eBirdApiToken"] = @api_key

      throttle
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: timeout) do |http|
        http.request(request)
      end

      @remaining_quota = response["ratelimit"].to_s[/"policy";r=(\d+)/, 1]&.to_i
      body = parse(response, path)
      RawPayload.record(feed: "ebird", path: path, status: response.code.to_i, body: body) if record
      body
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => e
      raise Unavailable, "#{path}: #{e.class}"
    end

    def throttle
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      wait = @last_request_at ? MIN_INTERVAL - (now - @last_request_at) : 0
      sleep(wait) if wait.positive?
      @last_request_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def parse(response, path)
      status = response.code.to_i
      raise RateLimited, "#{path}: quota exhausted" if status == 429
      raise Unavailable, "#{path}: HTTP #{status}" if status >= 500
      raise RequestError, "#{path}: HTTP #{status} #{response.body.to_s.first(200)}" if status >= 400

      body = JSON.parse(response.body)
      # eBird sometimes reports a failure in the body rather than the status.
      raise Unavailable, "#{path}: #{body["errors"].first["title"]}" if body.is_a?(Hash) && body["errors"].present?

      body
    rescue JSON::ParserError
      raise Unavailable, "#{path}: response is not JSON"
    end
  end
end
