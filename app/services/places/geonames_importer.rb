require "net/http"

module Places
  # Loads cities, towns and boroughs of the five provinces from GeoNames
  # (https://www.geonames.org, CC BY 4.0). Safe to re-run: places are
  # upserted on their GeoNames id. Provinces must be imported first.
  class GeonamesImporter
    # Every populated place with at least 500 inhabitants, worldwide.
    SOURCE_URL = "https://download.geonames.org/export/dump/cities500.zip".freeze
    ENTRY_NAME = "cities500.txt".freeze
    # GeoNames first-level administrative codes for Canada.
    PROVINCE_CODES = { "04" => "CA-NB", "07" => "CA-NS", "08" => "CA-ON", "09" => "CA-PE", "10" => "CA-QC" }.freeze
    # Feature code for a section of a populated place (borough, neighbourhood).
    SECTION_CODE = "PPLX".freeze
    CITY_RADIUS_KM = 25
    SECTION_RADIUS_KM = 10
    BATCH_SIZE = 1_000

    Row = Struct.new(:geonames_id, :name, :ascii_name, :alternate_names, :latitude, :longitude,
                     :feature_code, :province_code, :population, :timezone)

    def call
      provinces = Place.provinces.pluck(:province_code, :id).to_h
      missing = PROVINCE_CODES.values - provinces.keys
      raise "Provinces are missing (#{missing.join(", ")}): run places:import_ebird first" if missing.any?

      rows = download_rows
      rows.each_slice(BATCH_SIZE) do |batch|
        attributes = batch.map { |row| place_attributes(row, provinces) }
        Place.upsert_all(attributes, unique_by: :geonames_id, update_only: attributes.first.keys - %i[geonames_id])
      end
      add_aliases(rows)

      { cities: rows.size }
    end

    private

    def download_rows
      Tempfile.create([ "geonames", ".zip" ], binmode: true) do |file|
        response = Net::HTTP.get_response(URI(SOURCE_URL))
        raise "GeoNames download failed: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        file.write(response.body)
        file.flush
        Zip::File.open(file.path) { |zip| parse(zip.read(ENTRY_NAME).force_encoding(Encoding::UTF_8)) }
      end
    end

    # Tab-separated, one place per line; columns are documented at
    # https://download.geonames.org/export/dump/readme.txt
    def parse(text)
      text.each_line(chomp: true).filter_map do |line|
        columns = line.split("\t", -1)
        province_code = PROVINCE_CODES[columns[10]] if columns[8] == "CA"
        next unless province_code

        Row.new(columns[0].to_i, columns[1], columns[2], columns[3].split(","), columns[4].to_f, columns[5].to_f,
                columns[7], province_code, columns[14].to_i, columns[17])
      end
    end

    def place_attributes(row, provinces)
      {
        kind: "city",
        name: row.name,
        province_code: row.province_code,
        parent_id: provinces.fetch(row.province_code),
        geonames_id: row.geonames_id,
        latitude: row.latitude,
        longitude: row.longitude,
        default_radius_km: row.feature_code == SECTION_CODE ? SECTION_RADIUS_KM : CITY_RADIUS_KM,
        importance: row.population,
        details: { population: row.population, feature_code: row.feature_code, timezone: row.timezone }
      }
    end

    def add_aliases(rows)
      ids = Place.cities.pluck(:geonames_id, :id).to_h

      rows.each_slice(BATCH_SIZE) do |batch|
        aliases = batch.flat_map do |row|
          searchable_names(row).map do |name|
            { place_id: ids.fetch(row.geonames_id), name: name, normalized_name: PlaceAlias.normalize(name) }
          end
        end.uniq { |row| row.values_at(:place_id, :normalized_name) }

        PlaceAlias.insert_all(aliases, unique_by: %i[place_id normalized_name])
      end
    end

    # GeoNames lists alternate names in every language and script, plus
    # airport codes. Only variants that contain the place's own name are
    # kept ("Quebec City", "Ville de Québec"), which drops transliterations.
    def searchable_names(row)
      base = PlaceAlias.normalize(row.ascii_name)
      variants = row.alternate_names.select { |name| " #{PlaceAlias.normalize(name)} ".include?(" #{base} ") }

      [ row.name, row.ascii_name, *variants ].select { |name| PlaceAlias.normalize(name).present? }
    end
  end
end
