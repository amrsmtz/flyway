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
end
