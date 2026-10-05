module Inaturalist
  # Ingests observations created or changed since the last run: new
  # records, but also older ones whose identification or quality grade moved.
  class UpdatesHandler < BaseHandler
    # Re-read a few minutes before the previous run, in case records were
    # being written while it ran.
    OVERLAP = 5.minutes

    private

    def perform(unit)
      started_at = Time.current
      since = unit.scope["updated_since"] || 1.hour.ago.iso8601
      count = 0
      latest = nil

      each_page(unit, updated_since: since) do |records|
        rows = @normalizer.rows(records)
        next if rows.empty?

        replace(rows)
        count += rows.size
        latest = [ latest, rows.pluck(:observed_at).max ].compact.max
      end

      unit.update!(scope: { "updated_since" => (started_at - OVERLAP).iso8601 })
      { records: count, latest_data_at: latest }
    end

    # The observation time is part of the unique key, and observers can
    # change it. Deleting first keeps an edited record from being duplicated.
    def replace(rows)
      Observation.transaction do
        Observation.where(source: FEED, source_id: rows.pluck(:source_id)).delete_all
        Observation.insert_all(rows)
      end
    end
  end
end
