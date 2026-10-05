class CreateWeatherTables < ActiveRecord::Migration[8.1]
  def up
    # Where weather is sampled: a one-degree grid over the birded part of
    # the region, plus one point per featured site.
    create_table :weather_points do |t|
      t.string :kind, null: false
      t.references :place, foreign_key: true
      # Position asked for.
      t.float :latitude, null: false
      t.float :longitude, null: false
      # Centre of the weather model's grid cell that answered.
      t.float :model_latitude
      t.float :model_longitude
      t.float :elevation_m
      t.timestamps
    end
    add_index :weather_points, [ :latitude, :longitude ], unique: true

    create_table :weather_hours, id: false do |t|
      t.datetime :time, null: false
      t.references :weather_point, null: false
      t.float :temperature_c
      t.float :pressure_msl_hpa
      t.float :precipitation_mm
      t.float :cloud_cover_percent
      # Wind near the ground, then at about 750 m (925 hPa) and 1,500 m
      # (850 hPa), the heights at which most songbirds migrate.
      # Directions are where the wind comes from, in degrees.
      t.float :wind_speed_10m_kmh
      t.float :wind_direction_10m
      t.float :wind_speed_925hpa_kmh
      t.float :wind_direction_925hpa
      t.float :wind_speed_850hpa_kmh
      t.float :wind_direction_850hpa
      # True while the hour was still in the future when it was fetched.
      t.boolean :forecast, null: false, default: false
      t.datetime :fetched_at, null: false
    end
    execute "SELECT create_hypertable('weather_hours', by_range('time', INTERVAL '1 month'))"
    remove_index :weather_hours, :weather_point_id
    add_index :weather_hours, [ :weather_point_id, :time ], unique: true
  end

  def down
    drop_table :weather_hours
    drop_table :weather_points
  end
end
