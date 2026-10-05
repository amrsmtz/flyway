module Ebird
  # Finds the featured site, if any, whose radius contains a position.
  class SiteLocator
    EARTH_RADIUS_KM = 6371.0

    def initialize
      @sites = Place.sites.pluck(:id, :latitude, :longitude, :default_radius_km)
    end

    def site_id_for(latitude, longitude)
      @sites.filter_map do |id, site_latitude, site_longitude, radius_km|
        distance = distance_km(latitude, longitude, site_latitude, site_longitude)
        [ distance, id ] if distance <= radius_km
      end.min&.last
    end

    private

    # Haversine great-circle distance.
    def distance_km(latitude_a, longitude_a, latitude_b, longitude_b)
      to_radians = Math::PI / 180
      delta_latitude = (latitude_b - latitude_a) * to_radians
      delta_longitude = (longitude_b - longitude_a) * to_radians
      a = Math.sin(delta_latitude / 2)**2 +
          Math.cos(latitude_a * to_radians) * Math.cos(latitude_b * to_radians) * Math.sin(delta_longitude / 2)**2
      2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a))
    end
  end
end
