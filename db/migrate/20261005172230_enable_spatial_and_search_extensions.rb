class EnableSpatialAndSearchExtensions < ActiveRecord::Migration[8.1]
  def change
    enable_extension "postgis"
    enable_extension "h3"
    enable_extension "pg_trgm"
    enable_extension "unaccent"
  end
end
