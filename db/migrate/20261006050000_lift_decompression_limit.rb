class LiftDecompressionLimit < ActiveRecord::Migration[8.1]
  # Updating rows in a converted (columnstore) chunk makes TimescaleDB
  # decompress the batches that hold them, and it refuses past 100,000
  # tuples per transaction by default. A page of late iNaturalist updates
  # touches rows scattered over the whole year, which exceeded that limit
  # and stopped the feed. Writes here are small and bounded by page size,
  # so the limit is lifted for this database.
  def up
    execute "ALTER DATABASE #{connection.quote_table_name(connection.current_database)} " \
            "SET timescaledb.max_tuples_decompressed_per_dml_transaction = 0"
  end

  def down
    execute "ALTER DATABASE #{connection.quote_table_name(connection.current_database)} " \
            "RESET timescaledb.max_tuples_decompressed_per_dml_transaction"
  end
end
