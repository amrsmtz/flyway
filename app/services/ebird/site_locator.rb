module Ebird
  # Finds the featured site, if any, whose radius contains a position.
  class SiteLocator
    def initialize
      @sites = Place.sites.pluck(:id, :latitude, :longitude, :default_radius_km)
    end

    def site_id_for(latitude, longitude)
      @sites.filter_map do |id, site_latitude, site_longitude, radius_km|
        distance = Analytics::Geocoder.distance_km(latitude, longitude, site_latitude, site_longitude)
        [ distance, id ] if distance <= radius_km
      end.min&.last
    end
  end
end
