module Analytics
  module Tools
    # Night-by-night weather for a place, read the way a migrating bird
    # would: is the wind at flying height pushing along the seasonal
    # direction of travel, and is it raining? With a species group, it also
    # compares bird activity after favourable and unfavourable nights. That
    # is an association over a few nights, never proof of a cause.
    class WeatherContext < Base
      # Direction of travel in degrees: roughly south in fall, north in spring.
      HEADINGS = { fall: 190, spring: 10 }.freeze
      SEASON_MONTHS = { fall: 8..11, spring: 3..6 }.freeze
      # km/h of push along the heading above which a night helps or hinders.
      TAILWIND_THRESHOLD = 10
      RAIN_THRESHOLD_MM = 5
      MAX_NIGHTS = 14
      MAX_POINT_DISTANCE_KM = 120

      def initialize(place:, period:, group: nil)
        super()
        @place = place
        @area = Area.new(place)
        @period = period
        @group = group
      end

      def call
        point, distance_km = nearest_point
        return result(place: @area.name, period: @period.as_json, nights: [], notes: [ "No weather point near this place." ]) unless point

        nights = nights_for(point)
        flag("includes_forecast", "Some nights are forecasts, not yet observed weather.") if nights.any? { |night| night[:forecast] }
        add_evidence(point, nights)

        result(
          place: @area.name, period: @period.as_json,
          weather_point: { distance_km: distance_km.round, latitude: point.latitude.round(2), longitude: point.longitude.round(2) },
          wind_height: "about 750 m above ground (925 hPa), where most songbirds migrate at night",
          nights: nights.last(MAX_NIGHTS), nights_in_period: nights.size,
          favourable_nights: nights.count { |night| night[:verdict] == "favourable" },
          unfavourable_nights: nights.count { |night| night[:verdict] == "unfavourable" },
          activity_after_nights: (activity_after(nights) if @group),
          notes: weather_notes(distance_km)
        )
      end

      private

      # Weather is read at a single point; for a large area that is only
      # the weather near its centre.
      def weather_notes(distance_km)
        return [] if @area.site? || distance_km < 15

        [ "Weather is taken at one point #{distance_km.round} km from the centre of #{@area.name}; a large area can have different weather at its edges." ]
      end

      def nearest_point
        candidates = WeatherPoint.all.map do |point|
          [ Geocoder.distance_km(@place.latitude, @place.longitude, point.latitude, point.longitude), point ]
        end
        distance, point = candidates.min_by(&:first)
        [ point, distance ] if distance && distance <= MAX_POINT_DISTANCE_KM
      end

      # A night is labelled by the evening it starts on: the night of the
      # 4th runs into the morning of the 5th.
      def nights_for(point)
        zone = ActiveSupport::TimeZone["America/Toronto"]
        range = zone.local(@period.first_day.year, @period.first_day.month, @period.first_day.day, 12)..
                zone.local(@period.last_day.year, @period.last_day.month, @period.last_day.day, 12)

        WeatherNight.where(weather_point: point, night: range).order(:night).filter_map do |night|
          next if night.wind_speed_kmh.nil?

          describe(night)
        end
      end

      def describe(night)
        season = SEASON_MONTHS.find { |_, months| months.cover?(night.starts_on.month) }&.first
        tailwind = season && night.tailwind_kmh(HEADINGS.fetch(season)).round
        rain = night.precipitation_mm.to_f.round(1)

        {
          night_of: night.starts_on.iso8601,
          wind: "#{night.wind_from_compass} #{night.wind_speed_kmh.round} km/h",
          tailwind_kmh: tailwind, rain_mm: rain, pressure_change_hpa: night.pressure_change_hpa&.round(1),
          verdict: verdict(tailwind, rain), forecast: night.includes_forecast
        }
      end

      def verdict(tailwind, rain)
        return "outside migration season" if tailwind.nil?
        return "unfavourable" if rain >= RAIN_THRESHOLD_MM || tailwind <= -TAILWIND_THRESHOLD

        tailwind >= TAILWIND_THRESHOLD ? "favourable" : "neutral"
      end

      # Share of the group among iNaturalist bird records on the day after
      # each kind of night.
      def activity_after(nights)
        records = @period.apply(@area.observations("inaturalist"))
        totals = records.group(:observed_on).count
        in_group = records.where(species_group_id: @group.id).group(:observed_on).count

        summary = %w[favourable unfavourable].to_h do |kind|
          days = nights.select { |night| night[:verdict] == kind }.map { |night| Date.iso8601(night[:night_of]) + 1 }
          whole = days.sum { |day| totals[day].to_i }
          part = days.sum { |day| in_group[day].to_i }
          [ kind, { mornings: days.size, bird_records: whole, group_records: part, display: share_display(part, whole, "bird records") } ]
        end

        if summary.values.any? { |entry| entry[:mornings] < 3 || entry[:bird_records] < INATURALIST_TIERS[:low] }
          flag("few_nights", "Too few nights or records of each kind to compare what followed them.")
        end
        summary.merge(group: @group.name,
                      caveat: "An association over a few nights. Weather is only one of many things that change what observers report.")
      end

      def add_evidence(point, nights)
        evidence(
          title: "Night weather near #{@area.name}, #{@period}",
          method: "Open-Meteo hourly weather at #{point.latitude.round(2)}° N, #{(-point.longitude).round(2)}° W, " \
                  "averaged over the hours of darkness (20:00 to 06:00). Tailwind is the wind's push along the seasonal " \
                  "direction of travel; a night is favourable from #{TAILWIND_THRESHOLD} km/h of tailwind with under #{RAIN_THRESHOLD_MM} mm of rain.",
          source: "Open-Meteo",
          records: nights.last(EVIDENCE_SAMPLE).map do |night|
            { label: "Night of #{night[:night_of]}", date: night[:night_of],
              detail: "#{night[:wind]}, tailwind #{night[:tailwind_kmh] || "n/a"} km/h, rain #{night[:rain_mm]} mm, #{night[:verdict]}",
              url: "https://open-meteo.com/en/docs/historical-forecast-api?latitude=#{point.latitude.round(4)}&longitude=#{point.longitude.round(4)}&start_date=#{night[:night_of]}&end_date=#{night[:night_of]}&hourly=wind_speed_925hPa,wind_direction_925hPa" }
          end
        )
      end
    end
  end
end
