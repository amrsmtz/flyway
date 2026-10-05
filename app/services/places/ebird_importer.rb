module Places
  # Loads the provinces, counties and hotspots that eBird knows about into
  # the gazetteer. Safe to re-run: places are upserted on their eBird code,
  # and counties that already have a bounding box are not fetched again, so
  # an interrupted run resumes where it stopped.
  class EbirdImporter
    # Seconds between region lookups, to stay well under eBird's burst limit
    # of 25 requests per 5 seconds.
    PAUSE = 0.3
    HOTSPOT_RADIUS_KM = 2
    BATCH_SIZE = 2_000

    def initialize(client: Ebird::Client.new, pause: PAUSE)
      @client = client
      @pause = pause
    end

    def call
      result = { provinces: 0, counties: 0, counties_without_geometry: [], hotspots: 0 }

      Place::PROVINCES.each do |definition|
        province = import_province(definition)
        pending = import_counties(province)
        hotspots = import_hotspots(province)
        skipped = pending.reject { |region| county_from_hotspots(province, region, hotspots) }

        result[:provinces] += 1
        result[:counties] += Place.counties.where(province_code: province.province_code).count
        result[:counties_without_geometry].concat(skipped.map { |region| region.fetch("code") })
        result[:hotspots] += hotspots.size
      end

      result
    end

    private

    def import_province(definition)
      province = Place.find_or_initialize_by(ebird_code: definition[:code])
      province.assign_attributes(region_attributes(definition[:code]) || {}) unless province.bounding_box?
      province.update!(
        kind: "province",
        name: definition[:name],
        province_code: definition[:code],
        inaturalist_place_id: definition[:inaturalist_place_id]
      )
      add_aliases(province.id => [ definition[:name], *definition[:aliases] ])
      province
    end

    # Returns the regions eBird lists without any geometry, to be located
    # from their hotspots instead.
    def import_counties(province)
      @client.sub_regions(province.ebird_code).reject do |region|
        county = Place.find_or_initialize_by(ebird_code: region.fetch("code"))
        next true if county.persisted? && county.bounding_box?

        geometry = region_attributes(region.fetch("code"))
        save_county(county, province, region, geometry) if geometry
      end
    end

    def save_county(county, province, region, geometry)
      county.update!(kind: "county", name: region.fetch("name"), province_code: province.province_code,
                     parent: province, **geometry)
      add_aliases(county.id => [ county.name ])
      county
    end

    # Some regions come back from eBird with no bounds and a 0,0 centre.
    def region_attributes(region_code)
      sleep @pause
      info = @client.region_info(region_code)
      bounds = info["bounds"]
      return if bounds.blank?

      {
        latitude: info.fetch("latitude"),
        longitude: info.fetch("longitude"),
        min_latitude: bounds.fetch("minY"),
        max_latitude: bounds.fetch("maxY"),
        min_longitude: bounds.fetch("minX"),
        max_longitude: bounds.fetch("maxX")
      }
    end

    def import_hotspots(province)
      hotspots = @client.hotspots(province.ebird_code)
      county_ids = Place.counties.where(province_code: province.province_code).pluck(:ebird_code, :id).to_h

      hotspots.each_slice(BATCH_SIZE) do |batch|
        rows = batch.map { |hotspot| hotspot_attributes(hotspot, province, county_ids) }
        Place.upsert_all(rows, unique_by: :ebird_code, update_only: rows.first.keys - %i[ebird_code])
      end

      names = hotspots.to_h { |hotspot| [ hotspot.fetch("locId"), hotspot.fetch("locName") ] }
      Place.hotspots.where(province_code: province.province_code).pluck(:id, :ebird_code).each_slice(BATCH_SIZE) do |batch|
        add_aliases(batch.to_h { |id, code| [ id, hotspot_names(names[code]) ] })
      end

      hotspots
    end

    # Fallback for a county without geometry: centre and bounding box of its
    # hotspots. Returns nil when it has no hotspot either.
    def county_from_hotspots(province, region, hotspots)
      members = hotspots.select { |hotspot| hotspot["subnational2Code"] == region.fetch("code") }
      return if members.empty?

      latitudes = members.map { |hotspot| hotspot.fetch("lat") }
      longitudes = members.map { |hotspot| hotspot.fetch("lng") }
      geometry = {
        latitude: latitudes.sum / latitudes.size, longitude: longitudes.sum / longitudes.size,
        min_latitude: latitudes.min, max_latitude: latitudes.max,
        min_longitude: longitudes.min, max_longitude: longitudes.max,
        details: { geometry_source: "hotspots" }
      }

      county = save_county(Place.find_or_initialize_by(ebird_code: region.fetch("code")), province, region, geometry)
      Place.hotspots.where(ebird_code: members.map { |hotspot| hotspot.fetch("locId") }).update_all(parent_id: county.id)
      county
    end

    def hotspot_attributes(hotspot, province, county_ids)
      {
        kind: "hotspot",
        name: hotspot.fetch("locName"),
        province_code: province.province_code,
        parent_id: county_ids[hotspot["subnational2Code"]] || province.id,
        ebird_code: hotspot.fetch("locId"),
        latitude: hotspot.fetch("lat"),
        longitude: hotspot.fetch("lng"),
        default_radius_km: HOTSPOT_RADIUS_KM,
        importance: hotspot["numChecklistsAllTime"].to_i,
        details: {
          species_all_time: hotspot["numSpeciesAllTime"],
          checklists_all_time: hotspot["numChecklistsAllTime"],
          latest_observation_at: hotspot["latestObsDt"]
        }
      }
    end

    # eBird appends advice in parentheses to some names, such as
    # "(utilisez un site plus précis)"; the bare name is searchable too.
    def hotspot_names(name)
      return [] if name.blank?

      [ name, name.gsub(/\s*\([^)]*\)/, "").strip ].uniq
    end

    def add_aliases(names_by_place_id)
      rows = names_by_place_id.flat_map do |place_id, names|
        names.filter_map do |name|
          normalized = PlaceAlias.normalize(name)
          { place_id: place_id, name: name, normalized_name: normalized } if normalized.present?
        end
      end.uniq { |row| row.values_at(:place_id, :normalized_name) }

      PlaceAlias.insert_all(rows, unique_by: %i[place_id normalized_name]) if rows.any?
    end
  end
end
