module Analytics
  # Selects the observations and checklists that belong to a place, however
  # the place is defined: a radius, a list of counties, provinces or a
  # bounding box. It also says where that selection is only approximate.
  class Area
    # Distance filter per table: rows within a number of metres of a point.
    WITHIN_DISTANCE = %w[observations checklists].index_with do |table|
      "ST_DWithin(ST_SetSRID(ST_MakePoint(#{table}.longitude, #{table}.latitude), 4326)::geography, " \
        "ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)"
    end.freeze
    KM_PER_DEGREE = 111.0

    attr_reader :place

    def initialize(place)
      @place = place
      @area = place.search_area
    end

    def name
      @place.name
    end

    def site?
      @place.kind == "site"
    end

    # Observations of one source inside the area.
    def observations(source)
      scope = Observation.where(source: source)

      case @area[:type]
      when "radius" then within_radius(scope, "observations")
      when "provinces" then scope.where(province_code: @area[:province_codes])
      when "bounding_box" then within_box(scope.where(province_code: @area[:province_codes]), @area)
      when "counties"
        # iNaturalist records carry no county; the counties' bounding box
        # stands in for them (see #notes).
        source == "ebird" ? scope.where(county_code: @area[:county_codes]) : within_box(scope.where(province_code: @place.province_code), box)
      end
    end

    # First day for which full checklists are held, or nil. They are only
    # collected for recent weeks.
    def checklists_since
      checklists.minimum(:observed_on)
    end

    # Full eBird checklists inside the area. Only featured sites have them.
    def checklists
      return Checklist.where(site_id: @place.id) if site?
      return within_radius(Checklist.all, "checklists") if @area[:type] == "radius"

      Checklist.none
    end

    # Counties of the area for which eBird's daily effort figures are
    # collected (the counties of featured sites).
    def effort_county_codes
      codes = case @area[:type]
      when "counties" then @area[:county_codes]
      when "provinces" then Place.counties.where(province_code: @area[:province_codes]).pluck(:ebird_code)
      when "radius" then counties_of_nearby_hotspots
      else counties_in_box
      end

      codes & self.class.covered_county_codes
    end

    def self.covered_county_codes
      Rails.cache.fetch("analytics/covered_counties", expires_in: 10.minutes) do
        RegionDayEffort.where(source: "ebird").distinct.pluck(:county_code)
      end
    end

    # Plain-language caveats about how the area was matched to the data.
    def notes
      notes = []
      if @area[:type] == "counties"
        notes << "iNaturalist records are selected by a rectangle around the counties, which takes in some neighbouring land."
      end
      if effort_county_codes.empty? && checklists.none?
        notes << "eBird is collected only for the counties of featured birding sites; none of them is in this area."
      elsif !site? && @area[:type] != "counties"
        notes << "eBird covers only part of this area (the counties of featured birding sites)."
      end
      notes
    end

    # [min_latitude, max_latitude, min_longitude, max_longitude] enclosing the area.
    def box
      if @area[:type] == "radius"
        latitude_span = @area[:radius_km] / KM_PER_DEGREE
        longitude_span = latitude_span / Math.cos(@place.latitude * Math::PI / 180)
        { min_latitude: @place.latitude - latitude_span, max_latitude: @place.latitude + latitude_span,
          min_longitude: @place.longitude - longitude_span, max_longitude: @place.longitude + longitude_span }
      else
        @place.slice(:min_latitude, :max_latitude, :min_longitude, :max_longitude).symbolize_keys
      end
    end

    private

    # The box filter comes first so the exact distance is only computed for
    # nearby rows.
    def within_radius(scope, table)
      within_box(scope, box).where(WITHIN_DISTANCE.fetch(table), @place.longitude, @place.latitude, @area[:radius_km] * 1000.0)
    end

    def within_box(scope, bounds)
      scope.where(latitude: bounds[:min_latitude]..bounds[:max_latitude], longitude: bounds[:min_longitude]..bounds[:max_longitude])
    end

    # A radius can straddle counties; those of its hotspots are the ones
    # birders there report to.
    def counties_of_nearby_hotspots
      Place.hotspots.within_km(@place.latitude, @place.longitude, @area[:radius_km])
           .joins(:parent).distinct.pluck("parents_places.ebird_code")
    end

    def counties_in_box
      bounds = box
      Place.counties.where(latitude: bounds[:min_latitude]..bounds[:max_latitude],
                           longitude: bounds[:min_longitude]..bounds[:max_longitude]).pluck(:ebird_code)
    end
  end
end
