module Ebird
  # Ingests one county and day: the effort eBird reports (checklists,
  # observers, species), one observation per species seen, and, when asked,
  # the checklists submitted near featured sites, queued for full retrieval.
  class CountyDayHandler < BaseHandler
    def initialize(...)
      super
      @sites = SiteLocator.new
    end

    private

    def perform(unit)
      county_code, date = unit.scope.values_at("county_code", "date")
      province_code = county_code[0, 5]
      stats = @client.region_stats(county_code, date)
      save_effort(county_code, date, stats)

      observations = stats["numChecklists"].to_i.zero? ? [] : @client.historic_observations(county_code, date)
      rows = observations.map { |observation| observation_attributes(observation, county_code, province_code) }
      Observation.upsert_all(rows, unique_by: Observation::UNIQUE_KEY, update_only: %i[quality_tier]) if rows.any?

      queue_site_checklists(unit, county_code, province_code, date) if unit.scope["checklists"] && observations.any?

      { records: rows.size, latest_data_at: rows.pluck(:observed_at).max }
    end

    def save_effort(county_code, date, stats)
      RegionDayEffort.upsert(
        { day: date, source: FEED, county_code: county_code, checklist_count: stats["numChecklists"].to_i,
          observer_count: stats["numContributors"], species_count: stats["numSpecies"], fetched_at: Time.current },
        unique_by: RegionDayEffort::UNIQUE_KEY
      )
    end

    def observation_attributes(observation, county_code, province_code)
      observed_at = parse_local_time(observation.fetch("obsDt"), province_code)

      {
        observed_at: observed_at, observed_on: observed_at.to_date, source: FEED,
        source_id: observation.fetch("obsId"), basis: "region_day",
        checklist_source_id: observation["subId"], county_code: county_code, province_code: province_code,
        latitude: observation.fetch("lat"), longitude: observation.fetch("lng"),
        individual_count: observation["howMany"], quality_tier: quality_tier(observation),
        details: { location_code: observation["locId"] },
        **taxon_attributes(observation.fetch("speciesCode"))
      }
    end

    # obsValid is false while a record awaits review or was rejected;
    # obsReviewed is true once a regional reviewer has looked at it.
    def quality_tier(observation)
      return "flagged" unless observation["obsValid"]

      observation["obsReviewed"] ? "confirmed" : "unreviewed"
    end

    def queue_site_checklists(unit, county_code, province_code, date)
      units = @client.checklist_feed(county_code, date).filter_map do |entry|
        location = entry.fetch("loc")
        site_id = @sites.site_id_for(location.fetch("latitude"), location.fetch("longitude"))
        next unless site_id

        { kind: "checklist", key: entry.fetch("subId"), priority: unit.priority,
          scope: { submission_id: entry.fetch("subId"), site_id: site_id, county_code: county_code,
                   province_code: province_code, location_code: entry.fetch("locId"),
                   latitude: location.fetch("latitude"), longitude: location.fetch("longitude") } }
      end

      IngestionUnit.enqueue(FEED, units)
    end
  end
end
