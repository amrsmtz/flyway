module OpenMeteo
  # Ingests past weather for a group of points over a period (backfill).
  class PeriodHandler < BaseHandler
    private

    def perform(unit)
      points = WeatherPoint.where(id: unit.scope.fetch("point_ids")).order(:id).to_a
      results = @client.historical(points, start_date: unit.scope.fetch("start_date"), end_date: unit.scope.fetch("end_date"))
      save(points, results)
    end
  end
end
