module Analytics
  # Night winds for the map: for each night of the window and each grid
  # point, the mean wind about 750 m up (925 hPa) during the hours of
  # darkness, as eastward and northward speeds in km/h.
  class WindCube
    TIME_ZONE = "America/Toronto".freeze

    def initialize(days: 365, today: Date.current)
      @first_day = today - days
      @last_day = today
    end

    def as_json(*)
      points = WeatherPoint.where(kind: "grid").order(:id).pluck(:id, :latitude, :longitude)
      point_index = points.each_with_index.to_h { |(id, _, _), index| [ id, index ] }
      nights = Array.new((@last_day - @first_day).to_i + 1) { Array.new(points.size * 2) }
      forecast = Array.new(nights.size, false)

      rows.each do |night, point_id, u, v, includes_forecast|
        offset = (night.in_time_zone(TIME_ZONE).to_date - @first_day).to_i
        index = point_index[point_id]
        next unless index && nights[offset] && u

        nights[offset][index * 2] = u.round
        nights[offset][index * 2 + 1] = v.round
        forecast[offset] ||= includes_forecast
      end

      {
        first_day: @first_day.iso8601,
        # nights[n] is the night that begins on the evening of day n.
        points: points.map { |_, latitude, longitude| [ longitude, latitude ] },
        nights: nights,
        forecast: forecast
      }
    end

    private

    def rows
      WeatherNight
        .where(night: @first_day.in_time_zone(TIME_ZONE)..@last_day.in_time_zone(TIME_ZONE).end_of_day)
        .where(weather_point_id: WeatherPoint.where(kind: "grid").select(:id))
        .pluck(:night, :weather_point_id, :wind_u_925hpa, :wind_v_925hpa, :includes_forecast)
    end
  end
end
