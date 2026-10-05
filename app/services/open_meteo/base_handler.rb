module OpenMeteo
  class BaseHandler
    FEED = "open_meteo".freeze
    BATCH_SIZE = 2_000
    # Pause between units: Open-Meteo counts long periods and many points
    # as several calls against its hourly limit.
    PAUSE = 8

    def initialize(client: Client.new)
      @client = client
    end

    def call(unit)
      result = perform(unit)
      sleep PAUSE
      result
    rescue Client::RateLimited => e
      raise Ingestion::Runner::Paused.new(1.hour.from_now, e.message)
    rescue Client::Unavailable => e
      raise Ingestion::Runner::Retryable, e.message
    end

    private

    # results holds one API result per point, in the same order as points.
    def save(points, results)
      fetched_at = Time.current
      rows = points.zip(results).flat_map { |point, result| hours(point, result, fetched_at) }
      rows.each_slice(BATCH_SIZE) { |batch| WeatherHour.upsert_all(batch, unique_by: WeatherHour::UNIQUE_KEY) }

      points.zip(results).each do |point, result|
        next if point.model_latitude

        point.update!(model_latitude: result["latitude"], model_longitude: result["longitude"], elevation_m: result["elevation"])
      end

      { records: rows.size, latest_data_at: rows.reject { |row| row[:forecast] }.pluck(:time).max }
    end

    def hours(point, result, fetched_at)
      hourly = result.fetch("hourly")

      hourly.fetch("time").each_with_index.map do |time, index|
        time = Time.utc(*time.scan(/\d+/).map(&:to_i))
        values = Client::VARIABLES.to_h { |variable, column| [ column, hourly.fetch(variable)[index] ] }
        { time: time, weather_point_id: point.id, forecast: time > fetched_at, fetched_at: fetched_at, **values }
      end
    end
  end
end
