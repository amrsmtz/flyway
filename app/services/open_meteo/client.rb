require "net/http"

module OpenMeteo
  # Thin wrapper around Open-Meteo (no key needed, non-commercial use).
  # Everything comes from the historical forecast API, which, unlike the
  # reanalysis archive, includes winds at altitude.
  class Client
    HISTORICAL_URL = "https://historical-forecast-api.open-meteo.com/v1/forecast".freeze
    # API variable => weather_hours column.
    VARIABLES = {
      "temperature_2m" => :temperature_c, "pressure_msl" => :pressure_msl_hpa,
      "precipitation" => :precipitation_mm, "cloud_cover" => :cloud_cover_percent,
      "wind_speed_10m" => :wind_speed_10m_kmh, "wind_direction_10m" => :wind_direction_10m,
      "wind_speed_925hPa" => :wind_speed_925hpa_kmh, "wind_direction_925hPa" => :wind_direction_925hpa,
      "wind_speed_850hPa" => :wind_speed_850hpa_kmh, "wind_direction_850hPa" => :wind_direction_850hpa
    }.freeze

    class Error < StandardError; end
    class RateLimited < Error; end
    class Unavailable < Error; end
    class RequestError < Error; end

    # Hourly weather for each point over a period, which may extend a few
    # days into the future. Returns one result per point, in the order given.
    def historical(points, start_date:, end_date:)
      get(HISTORICAL_URL, points, start_date: start_date.to_s, end_date: end_date.to_s)
    end

    private

    def get(url, points, **params)
      uri = URI(url)
      uri.query = URI.encode_www_form(
        latitude: points.map(&:latitude).join(","), longitude: points.map(&:longitude).join(","),
        hourly: VARIABLES.keys.join(","), timezone: "UTC", **params
      )
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 90) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end

      # A single point comes back as an object, several as an array.
      Array.wrap(parse(response))
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => e
      raise Unavailable, e.class.to_s
    end

    def parse(response)
      status = response.code.to_i
      raise RateLimited, "too many requests" if status == 429
      raise Unavailable, "HTTP #{status}" if status >= 500

      body = JSON.parse(response.body)
      raise RequestError, "HTTP #{status} #{body["reason"]}" if status >= 400

      body
    rescue JSON::ParserError
      raise Unavailable, "response is not JSON"
    end
  end
end
