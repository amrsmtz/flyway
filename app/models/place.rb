class Place < ApplicationRecord
  KINDS = %w[province region county city site hotspot].freeze

  # The five provinces in scope, with the identifiers each feed uses.
  PROVINCES = [
    { code: "CA-QC", name: "Quebec", inaturalist_place_id: 13336,
      aliases: [ "Québec", "QC", "Province of Quebec", "Province de Québec" ] },
    { code: "CA-ON", name: "Ontario", inaturalist_place_id: 6883,
      aliases: [ "ON", "Ont." ] },
    { code: "CA-NB", name: "New Brunswick", inaturalist_place_id: 7587,
      aliases: [ "Nouveau-Brunswick", "NB", "N.B." ] },
    { code: "CA-NS", name: "Nova Scotia", inaturalist_place_id: 6853,
      aliases: [ "Nouvelle-Écosse", "NS", "N.S." ] },
    { code: "CA-PE", name: "Prince Edward Island", inaturalist_place_id: 9116,
      aliases: [ "Île-du-Prince-Édouard", "PEI", "P.E.I.", "PE" ] }
  ].freeze

  # Geography point of a place, for distance queries in SQL. Must match the
  # expression indexed by index_places_on_location.
  LOCATION_SQL = "(ST_SetSRID(ST_MakePoint(places.longitude, places.latitude), 4326)::geography)".freeze

  belongs_to :parent, class_name: "Place", optional: true
  has_many :children, class_name: "Place", foreign_key: :parent_id, dependent: :nullify
  has_many :aliases, class_name: "PlaceAlias", dependent: :delete_all

  validates :name, :latitude, :longitude, presence: true
  validates :kind, inclusion: { in: KINDS }

  KINDS.each { |kind| scope kind.pluralize, -> { where(kind: kind) } }

  scope :within_km, ->(latitude, longitude, radius_km) {
    where("ST_DWithin(#{LOCATION_SQL}, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)",
          longitude, latitude, radius_km * 1000.0)
  }

  def bounding_box?
    [ min_latitude, min_longitude, max_latitude, max_longitude ].all?
  end

  # How observations for this place are selected: a list of provinces or
  # counties, a bounding box, or a radius around its position.
  def search_area
    case kind
    when "province" then { type: "provinces", province_codes: [ province_code ] }
    when "county" then { type: "counties", county_codes: [ ebird_code ] }
    when "region" then region_search_area
    else { type: "radius", latitude: latitude, longitude: longitude, radius_km: default_radius_km }
    end
  end

  private

  # details["area"] records how the region was defined in config/gazetteer.yml.
  def region_search_area
    case details["area"]
    when "counties"
      { type: "counties", county_codes: details["county_codes"] }
    when "bounding_box"
      { type: "bounding_box", province_codes: details["province_codes"], min_latitude: min_latitude,
        max_latitude: max_latitude, min_longitude: min_longitude, max_longitude: max_longitude }
    else
      { type: "provinces", province_codes: details["province_codes"] }
    end
  end
end
