module Ebird
  # Ingests one full checklist: its effort (duration, distance, whether
  # every species was reported) and each species on it.
  class ChecklistHandler < BaseHandler
    private

    def perform(unit)
      scope = unit.scope
      checklist = @client.checklist(scope.fetch("submission_id"))
      observed_at = parse_local_time(checklist.fetch("obsDt"), scope.fetch("province_code"))

      Checklist.upsert(checklist_attributes(checklist, scope, observed_at), unique_by: Checklist::UNIQUE_KEY)
      rows = checklist.fetch("obs").map { |observation| observation_attributes(observation, checklist, scope, observed_at) }
      if rows.any?
        Observation.upsert_all(rows, unique_by: Observation::UNIQUE_KEY,
                                     update_only: %i[basis checklist_source_id individual_count])
      end

      { records: rows.size, latest_data_at: observed_at }
    end

    def checklist_attributes(checklist, scope, observed_at)
      {
        observed_at: observed_at, observed_on: observed_at.to_date, source: FEED,
        source_id: checklist.fetch("subId"), site_id: scope["site_id"],
        place_id: Place.hotspots.where(ebird_code: checklist["locId"]).pick(:id),
        location_code: checklist["locId"], county_code: scope["county_code"], province_code: scope["province_code"],
        latitude: scope.fetch("latitude"), longitude: scope.fetch("longitude"),
        protocol: checklist["protocolId"], duration_hours: checklist["durationHrs"],
        distance_km: checklist["effortDistanceKm"], complete: checklist["allObsReported"] == true,
        observer_count: checklist["numObservers"], species_count: checklist["numSpecies"],
        group_code: checklist["groupId"],
        source_created_at: parse_local_time(checklist["creationDt"], scope.fetch("province_code")),
        source_updated_at: parse_local_time(checklist["lastEditedDt"], scope.fetch("province_code"))
      }
    end

    def observation_attributes(observation, checklist, scope, observed_at)
      {
        observed_at: observed_at, observed_on: observed_at.to_date, source: FEED,
        source_id: observation.fetch("obsId"), basis: "checklist", checklist_source_id: checklist.fetch("subId"),
        county_code: scope["county_code"], province_code: scope["province_code"],
        latitude: scope.fetch("latitude"), longitude: scope.fetch("longitude"),
        individual_count: individual_count(observation),
        # Review status is only published per county and day; the matching
        # region_day record, when there is one, sets the tier.
        quality_tier: "unreviewed", details: { location_code: checklist["locId"] },
        **taxon_attributes(observation.fetch("speciesCode"))
      }
    end

    # "X" means present but not counted.
    def individual_count(observation)
      observation["howManyStr"] == "X" ? nil : observation["howManyAtleast"]
    end
  end
end
