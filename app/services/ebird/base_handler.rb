module Ebird
  # Shared behaviour of eBird unit handlers: one API client per run, API
  # failures translated for the runner, and a pause before the hourly quota
  # runs out.
  class BaseHandler
    FEED = "ebird".freeze
    # Stop this many calls before the hourly quota is exhausted.
    QUOTA_RESERVE = 20
    # eBird reports observation times in local time, without a zone.
    TIME_ZONES = {
      "CA-QC" => "America/Toronto", "CA-ON" => "America/Toronto",
      "CA-NB" => "America/Halifax", "CA-NS" => "America/Halifax", "CA-PE" => "America/Halifax"
    }.transform_values { |name| ActiveSupport::TimeZone[name] }.freeze

    def initialize(client: Client.new)
      @client = client
      @taxa = Taxonomy::Lookup.new
    end

    def call(unit)
      result = perform(unit)
      pause_feed("hourly quota nearly used") if @client.remaining_quota && @client.remaining_quota < QUOTA_RESERVE
      result.merge(remaining_quota: @client.remaining_quota)
    rescue Client::RateLimited => e
      raise Ingestion::Runner::Paused.new(next_quota_window, e.message)
    rescue Client::Unavailable => e
      raise Ingestion::Runner::Retryable, e.message
    end

    private

    def pause_feed(reason)
      FeedStatus.pause(FEED, next_quota_window, reason)
    end

    # The quota is counted per clock hour.
    def next_quota_window
      Time.current.beginning_of_hour + 1.hour + 1.minute
    end

    # "2026-10-04 12:52" or "2026-10-04", in the province's local time.
    # Observations without a time are placed at local midnight.
    def parse_local_time(text, province_code)
      TIME_ZONES.fetch(province_code).parse(text) if text.present?
    end

    def taxon_attributes(species_code)
      entry = @taxa.by_species_code(species_code)
      { taxon_id: entry&.taxon_id, species_id: entry&.species_id, species_group_id: entry&.species_group_id }
    end
  end
end
