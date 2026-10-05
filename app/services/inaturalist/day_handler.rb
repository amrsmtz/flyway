module Inaturalist
  # Ingests every bird observation made on one day (backfill).
  class DayHandler < BaseHandler
    private

    def perform(unit)
      date = unit.scope.fetch("date")
      count = 0
      latest = nil

      each_page(unit, d1: date, d2: date) do |records|
        rows = @normalizer.rows(records)
        next if rows.empty?

        Observation.upsert_all(rows, unique_by: Observation::UNIQUE_KEY, update_only: UPDATABLE)
        count += rows.size
        latest = [ latest, rows.pluck(:observed_at).max ].compact.max
      end

      { records: count, latest_data_at: latest }
    end
  end
end
