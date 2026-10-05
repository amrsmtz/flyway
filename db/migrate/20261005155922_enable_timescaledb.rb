class EnableTimescaledb < ActiveRecord::Migration[8.1]
  def change
    enable_extension "timescaledb"
  end
end
