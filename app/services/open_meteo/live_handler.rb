module OpenMeteo
  # Refreshes the last days and the coming ones for a group of points. It
  # uses the historical forecast API as well: that API also serves today
  # and the next days, and answers multi-point requests in a second or two
  # where the live forecast API took close to a minute.
  class LiveHandler < BaseHandler
    PAST_DAYS = 3
    FORECAST_DAYS = 2

    private

    def perform(unit)
      points = WeatherPoint.where(id: unit.scope.fetch("point_ids")).order(:id).to_a
      today = Time.now.utc.to_date
      save(points, @client.historical(points, start_date: today - PAST_DAYS, end_date: today + FORECAST_DAYS))
    end
  end
end
