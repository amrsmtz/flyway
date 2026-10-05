module Inaturalist
  # Ingests observations created or changed since the last run: new
  # records, but also older ones whose identification or quality grade moved.
  class UpdatesHandler < BaseHandler
    # Re-read a few minutes before the previous run, in case records were
    # being written while it ran.
    OVERLAP = 5.minutes
    # Chunks younger than this are not converted to columnstore yet.
    MOVED_RECORDS_WINDOW = 55.days

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

    # Most updates change an identification or a quality grade and keep
    # the observation time, so an upsert on the unique key is enough. The
    # time is part of that key, though, and observers can edit it: copies of
    # these records with another time are deleted first, among recent rows
    # only. Looking for them across the whole year would mean decompressing
    # every converted chunk, so an old record whose date is edited can
    # remain twice.
    def replace(rows)
      Observation.transaction do
        Observation.where(source: FEED, source_id: rows.pluck(:source_id), observed_at: MOVED_RECORDS_WINDOW.ago..)
                   .where.not(observed_at: rows.pluck(:observed_at)).delete_all
        Observation.upsert_all(rows, unique_by: Observation::UNIQUE_KEY, update_only: UPDATABLE)
      end
    end
  end
end
