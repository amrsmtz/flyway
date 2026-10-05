module Analytics
  module Geocoder
    EARTH_RADIUS_KM = 6371.0

    # Great-circle (haversine) distance between two positions.
    def self.distance_km(latitude_a, longitude_a, latitude_b, longitude_b)
      to_radians = Math::PI / 180
      delta_latitude = (latitude_b - latitude_a) * to_radians
      delta_longitude = (longitude_b - longitude_a) * to_radians
      a = Math.sin(delta_latitude / 2)**2 +
          Math.cos(latitude_a * to_radians) * Math.cos(latitude_b * to_radians) * Math.sin(delta_longitude / 2)**2
      2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a))
    end
  end
end
