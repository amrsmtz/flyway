module Inaturalist
  # Turns iNaturalist observation records into rows of the observations table.
  class Normalizer
    SOURCE = "inaturalist".freeze
    QUALITY_TIERS = { "research" => "confirmed", "needs_id" => "unreviewed", "casual" => "casual" }.freeze
    TIME_ZONES = Ebird::BaseHandler::TIME_ZONES

    def initialize(matcher: TaxonMatcher.new)
      @matcher = matcher
      @provinces = Place::PROVINCES.to_h { |province| [ province[:inaturalist_place_id], province[:code] ] }
    end

    # Records without a date, a position or a province in scope are skipped.
    def rows(records)
      records.filter_map { |record| row(record) }
    end

    private

    def row(record)
      province_code = @provinces.values_at(*record["place_ids"].to_a).compact.first
      latitude, longitude = record["location"].to_s.split(",").map(&:to_f)
      return if province_code.nil? || latitude.nil? || record["observed_on"].blank?

      observed_at = observed_at(record, province_code)
      match = @matcher.match(record["taxon"])

      {
        observed_at: observed_at, observed_on: record.fetch("observed_on"), source: SOURCE,
        source_id: record.fetch("id").to_s, basis: "record", province_code: province_code,
        latitude: latitude, longitude: longitude, quality_tier: QUALITY_TIERS.fetch(record["quality_grade"], "casual"),
        obscured: record["obscured"] == true,
        positional_accuracy_m: record["public_positional_accuracy"] || record["positional_accuracy"],
        taxon_id: match.taxon_id, species_id: match.species_id, species_group_id: match.species_group_id,
        details: details(record), source_updated_at: record["updated_at"]
      }
    end

    # Observations without a time are placed at local midnight.
    def observed_at(record, province_code)
      return Time.iso8601(record["time_observed_at"]) if record["time_observed_at"].present?

      TIME_ZONES.fetch(province_code).parse(record.fetch("observed_on"))
    end

    def details(record)
      photo = record["photos"].to_a.first
      {
        observer: record.dig("user", "login"),
        taxon_name: record.dig("taxon", "name"),
        identification_agreements: record["num_identification_agreements"],
        identification_disagreements: record["num_identification_disagreements"],
        # The API returns the 75-pixel square; "medium" is the display size.
        photo_url: photo && photo["url"]&.sub("/square.", "/medium."),
        photo_license: photo && photo["license_code"],
        photo_attribution: photo && photo["attribution"]
      }.compact
    end
  end
end
