class CreateContinuousAggregates < ActiveRecord::Migration[8.1]
  # Days and nights are cut in Eastern time for the whole region; in the
  # Maritimes, one hour ahead, buckets are shifted by that hour.
  TIME_ZONE = "America/Toronto".freeze
  # A night runs from local noon to the next noon, so that one bucket holds
  # one night of migration. (A time zone combined with "offset" crashes
  # TimescaleDB 2.30 on refresh; "origin" at noon gives the same buckets.)
  NOON_ORIGIN = "2000-01-01 12:00:00-05".freeze
  # Local hours counted as night: 20:00 to 05:59.
  NIGHT_HOURS = "(extract(hour from time AT TIME ZONE '#{TIME_ZONE}') >= 20 OR extract(hour from time AT TIME ZONE '#{TIME_ZONE}') < 6)".freeze
  # Wind direction is where the wind comes from. u and v are the eastward
  # and northward speeds of the air itself, which can be averaged.
  WIND_U = "(-wind_speed_%<level>s_kmh * sin(radians(wind_direction_%<level>s)))".freeze
  WIND_V = "(-wind_speed_%<level>s_kmh * cos(radians(wind_direction_%<level>s)))".freeze

  VIEWS = %w[observation_daily_cells observation_daily_species weather_nights weather_days].freeze

  def up
    # Map layer: observations per day, source, H3 cell (resolution 5, about
    # 250 km²) and featured group. Obscured positions are left out: they are
    # only accurate to about 20 km, more than a cell.
    execute <<~SQL
      CREATE MATERIALIZED VIEW observation_daily_cells WITH (timescaledb.continuous) AS
      SELECT time_bucket('1 day', observed_at, '#{TIME_ZONE}') AS day,
             source,
             h3_cell_to_parent(h3_cell::h3index, 5)::bigint AS cell,
             species_group_id,
             count(*) AS record_count,
             count(*) FILTER (WHERE quality_tier = 'confirmed') AS confirmed_count
      FROM observations
      WHERE NOT obscured
      GROUP BY 1, 2, 3, 4
      WITH NO DATA
    SQL

    # Species per day, source and area, for comparisons between dates,
    # places and sources.
    execute <<~SQL
      CREATE MATERIALIZED VIEW observation_daily_species WITH (timescaledb.continuous) AS
      SELECT time_bucket('1 day', observed_at, '#{TIME_ZONE}') AS day,
             source,
             province_code,
             county_code,
             species_id,
             species_group_id,
             count(*) AS record_count,
             count(*) FILTER (WHERE quality_tier = 'confirmed') AS confirmed_count,
             count(*) FILTER (WHERE quality_tier = 'flagged') AS flagged_count,
             max(individual_count) AS max_individual_count
      FROM observations
      GROUP BY 1, 2, 3, 4, 5, 6
      WITH NO DATA
    SQL

    # One row per point and night: mean wind during the hours of darkness,
    # rain, and how pressure and temperature moved from noon to noon.
    execute <<~SQL
      CREATE MATERIALIZED VIEW weather_nights WITH (timescaledb.continuous) AS
      SELECT time_bucket('1 day', time, '#{TIME_ZONE}', origin => '#{NOON_ORIGIN}'::timestamptz) AS night,
             weather_point_id,
             avg(#{format(WIND_U, level: "925hpa")}) FILTER (WHERE #{NIGHT_HOURS}) AS wind_u_925hpa,
             avg(#{format(WIND_V, level: "925hpa")}) FILTER (WHERE #{NIGHT_HOURS}) AS wind_v_925hpa,
             avg(#{format(WIND_U, level: "10m")}) FILTER (WHERE #{NIGHT_HOURS}) AS wind_u_10m,
             avg(#{format(WIND_V, level: "10m")}) FILTER (WHERE #{NIGHT_HOURS}) AS wind_v_10m,
             sum(precipitation_mm) FILTER (WHERE #{NIGHT_HOURS}) AS precipitation_mm,
             avg(cloud_cover_percent) FILTER (WHERE #{NIGHT_HOURS}) AS cloud_cover_percent,
             avg(temperature_c) FILTER (WHERE #{NIGHT_HOURS}) AS temperature_c,
             last(pressure_msl_hpa, time) - first(pressure_msl_hpa, time) AS pressure_change_hpa,
             last(temperature_c, time) - first(temperature_c, time) AS temperature_change_c,
             count(*) FILTER (WHERE #{NIGHT_HOURS}) AS night_hour_count,
             bool_or(forecast) AS includes_forecast
      FROM weather_hours
      GROUP BY 1, 2
      WITH NO DATA
    SQL

    # Daily means per point, for the timeline when zoomed out.
    execute <<~SQL
      CREATE MATERIALIZED VIEW weather_days WITH (timescaledb.continuous) AS
      SELECT time_bucket('1 day', time, '#{TIME_ZONE}') AS day,
             weather_point_id,
             avg(#{format(WIND_U, level: "925hpa")}) AS wind_u_925hpa,
             avg(#{format(WIND_V, level: "925hpa")}) AS wind_v_925hpa,
             avg(#{format(WIND_U, level: "10m")}) AS wind_u_10m,
             avg(#{format(WIND_V, level: "10m")}) AS wind_v_10m,
             sum(precipitation_mm) AS precipitation_mm,
             avg(temperature_c) AS temperature_c,
             bool_or(forecast) AS includes_forecast
      FROM weather_hours
      GROUP BY 1, 2
      WITH NO DATA
    SQL

    VIEWS.each do |view|
      # Real-time aggregation: buckets not materialised yet are computed on
      # read, so today's data shows without waiting for a refresh.
      execute "ALTER MATERIALIZED VIEW #{view} SET (timescaledb.materialized_only = false)"
      # No start offset: late data (backfills, reviews, edits) can land
      # anywhere in the year, and only invalidated buckets are recomputed.
      execute <<~SQL
        SELECT add_continuous_aggregate_policy('#{view}', start_offset => NULL,
                                               end_offset => INTERVAL '1 hour', schedule_interval => INTERVAL '15 minutes')
      SQL
    end
  end

  def down
    VIEWS.reverse_each { |view| execute "DROP MATERIALIZED VIEW IF EXISTS #{view}" }
  end
end
