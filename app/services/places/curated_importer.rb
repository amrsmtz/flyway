module Places
  # Loads the hand-curated birding sites and named regions from
  # config/gazetteer.yml. Safe to re-run: places are matched on their slug,
  # and entries removed from the file are deleted.
  # The eBird import must run first, since sites are anchored on hotspots
  # and regions are built from provinces and counties.
  class CuratedImporter
    SOURCE = Rails.root.join("config/gazetteer.yml")

    class InvalidDefinition < StandardError; end

    def call
      definitions = YAML.load_file(SOURCE)
      @provinces = Place.provinces.index_by(&:province_code)

      Place.transaction do
        result = {
          sites: definitions.fetch("sites").map { |definition| import_site(definition) },
          regions: definitions.fetch("regions").map { |definition| import_region(definition) }
        }
        remove_undefined(result.values.flatten)
        result
      end
    end

    private

    # The file is the source of truth: an entry deleted from it disappears.
    def remove_undefined(defined)
      Place.where(kind: %w[site region]).where.not(id: defined.map(&:id)).destroy_all
    end

    def import_site(definition)
      latitude, longitude = site_position(definition)
      radius_km = definition.fetch("radius_km")
      hotspots = Place.hotspots.within_km(latitude, longitude, radius_km)

      save(definition, kind: "site", featured: true, province_code: definition.fetch("province"),
           parent: province(definition.fetch("province")), latitude: latitude, longitude: longitude,
           default_radius_km: radius_km, importance: hotspots.sum(:importance),
           details: { description: definition["description"], anchor_ebird_code: definition["anchor"] }.compact)
    end

    def site_position(definition)
      return definition.values_at("latitude", "longitude") unless definition["anchor"]

      anchor = Place.hotspots.find_by(ebird_code: definition["anchor"])
      raise InvalidDefinition, "#{definition["slug"]}: unknown anchor hotspot #{definition["anchor"]}" unless anchor

      [ anchor.latitude, anchor.longitude ]
    end

    def import_region(definition)
      province_codes = Array(definition["provinces"] || definition.fetch("province"))
      counties = region_counties(definition)
      area = if counties.any? then "counties" elsif definition["bounds"] then "bounding_box" else "provinces" end
      bounds = definition["bounds"]&.symbolize_keys || union_bounds(counties.presence || province_codes.map { |code| province(code) })

      save(definition, kind: "region", **bounds,
           province_code: (province_codes.first if province_codes.one?),
           parent: (province(province_codes.first) if province_codes.one?),
           latitude: (bounds[:min_latitude] + bounds[:max_latitude]) / 2,
           longitude: (bounds[:min_longitude] + bounds[:max_longitude]) / 2,
           details: { area: area, province_codes: province_codes, county_codes: counties.map(&:ebird_code).presence }.compact)
    end

    def region_counties(definition)
      names = definition["counties"]
      return [] if names.blank?

      counties = Place.counties.where(province_code: definition.fetch("province"), name: names).to_a
      missing = names - counties.map(&:name)
      raise InvalidDefinition, "#{definition["slug"]}: unknown counties #{missing.join(", ")}" if missing.any?

      counties
    end

    def union_bounds(places)
      {
        min_latitude: places.map(&:min_latitude).min, max_latitude: places.map(&:max_latitude).max,
        min_longitude: places.map(&:min_longitude).min, max_longitude: places.map(&:max_longitude).max
      }
    end

    def province(code)
      @provinces.fetch(code) { raise InvalidDefinition, "unknown province #{code}: run places:import_ebird first" }
    end

    def save(definition, **attributes)
      place = Place.find_or_initialize_by(slug: definition.fetch("slug"))
      place.update!(name: definition.fetch("name"), **attributes)

      names = [ place.name, *definition["aliases"] ]
      rows = names.map { |name| { place_id: place.id, name: name, normalized_name: PlaceAlias.normalize(name) } }
      PlaceAlias.insert_all(rows.uniq { |row| row[:normalized_name] }, unique_by: %i[place_id normalized_name])
      place
    end
  end
end
