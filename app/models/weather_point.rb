class WeatherPoint < ApplicationRecord
  KINDS = %w[grid site].freeze
  # Grid extent, in whole degrees.
  GRID_LATITUDES = (42..50)
  GRID_LONGITUDES = (-84..-59)
  # A grid point is kept when at least this many eBird hotspots lie within
  # this distance: no need for weather where nobody birds.
  MIN_HOTSPOTS = 5
  HOTSPOT_RADIUS_KM = 45

  belongs_to :place, optional: true
  has_many :weather_hours, dependent: :delete_all

  validates :kind, inclusion: { in: KINDS }

  # Creates the missing points; safe to re-run.
  def self.sync!
    Place.sites.find_each do |site|
      create_with(kind: "site", place: site).find_or_create_by!(latitude: site.latitude, longitude: site.longitude)
    end

    GRID_LATITUDES.to_a.product(GRID_LONGITUDES.to_a).each do |latitude, longitude|
      next if Place.hotspots.within_km(latitude, longitude, HOTSPOT_RADIUS_KM).limit(MIN_HOTSPOTS).count < MIN_HOTSPOTS

      create_with(kind: "grid").find_or_create_by!(latitude: latitude, longitude: longitude)
    end

    count
  end
end
