module PlacesHelper
  KIND_LABELS = {
    "site" => "Birding site", "province" => "Province", "region" => "Region",
    "city" => "City or town", "county" => "County", "hotspot" => "eBird hotspot"
  }.freeze

  STATUS_MESSAGES = {
    found: "Match found.",
    ambiguous: "Several places share this name. The first one is used unless a province is given.",
    approximate: "No exact match. Showing the closest names.",
    not_found: "No place by that name in Quebec, Ontario or the Maritimes."
  }.freeze

  def place_kind_label(place)
    KIND_LABELS.fetch(place.kind)
  end

  def place_status_message(result)
    STATUS_MESSAGES.fetch(result.status)
  end

  # Plain-language description of how observations are gathered for a place.
  def place_search_area(place)
    area = place.search_area

    case area[:type]
    when "radius" then "Within #{number_with_precision(area[:radius_km], precision: 0)} km of #{coordinates(place)}"
    when "counties" then pluralize(area[:county_codes].size, "eBird county", plural: "eBird counties")
    when "provinces" then area[:province_codes].size == 1 ? "Whole province" : "#{area[:province_codes].size} provinces"
    when "bounding_box"
      "Rectangle from #{area[:min_latitude]}° to #{area[:max_latitude]}° N, #{-area[:max_longitude]}° to #{-area[:min_longitude]}° W"
    end
  end

  def coordinates(place)
    "#{number_with_precision(place.latitude, precision: 3)}° N, #{number_with_precision(-place.longitude, precision: 3)}° W"
  end

  # Link to the place on eBird when it has a page there.
  def place_ebird_url(place)
    code = place.ebird_code || place.details["anchor_ebird_code"]
    return if code.blank?

    code.start_with?("L") ? "https://ebird.org/hotspot/#{code}" : "https://ebird.org/region/#{code}"
  end
end
