class EnableColumnstore < ActiveRecord::Migration[8.1]
  # Old chunks are converted to TimescaleDB's columnstore (its compression).
  # Rows are grouped by the column queries filter on, and ordered by time.
  #
  # Observations and checklists wait 60 days: eBird reviews and iNaturalist
  # identifications keep changing records for weeks, and changing a
  # converted chunk is possible but slow. Weather settles within days.
  TABLES = {
    "weather_hours" => { segment_by: "weather_point_id", order_by: "time DESC", after: "30 days" },
    "observations" => { segment_by: "source", order_by: "observed_at DESC", after: "60 days" },
    "checklists" => { segment_by: "source", order_by: "observed_at DESC", after: "60 days" },
    "raw_payloads" => { segment_by: "feed", order_by: "fetched_at DESC", after: "7 days" }
  }.freeze

  def up
    TABLES.each do |table, options|
      execute <<~SQL
        ALTER TABLE #{table} SET (
          timescaledb.enable_columnstore = true,
          timescaledb.segmentby = '#{options[:segment_by]}',
          timescaledb.orderby = '#{options[:order_by]}'
        )
      SQL
      execute "CALL add_columnstore_policy('#{table}', after => INTERVAL '#{options[:after]}')"
    end
  end

  def down
    TABLES.each_key do |table|
      execute "CALL remove_columnstore_policy('#{table}', if_exists => true)"
    end
  end
end
