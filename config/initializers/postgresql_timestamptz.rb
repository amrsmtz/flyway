# Create datetime columns as "timestamp with time zone". TimescaleDB expects
# it for hypertables, and night and day boundaries here depend on time zones.
ActiveSupport.on_load(:active_record_postgresqladapter) do
  self.datetime_type = :timestamptz
end
