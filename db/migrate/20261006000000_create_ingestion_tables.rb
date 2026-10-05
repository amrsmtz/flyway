class CreateIngestionTables < ActiveRecord::Migration[8.1]
  def up
    # Work queue shared by every feed: one row per unit of work (a county
    # and day, a checklist, a week of observations...). A backfill is a set
    # of pending units, so it resumes after any interruption.
    create_table :ingestion_units do |t|
      t.string :feed, null: false
      t.string :kind, null: false
      # Identifies the unit within its feed and kind, e.g. "CA-QC-MR/2026-10-04".
      t.string :key, null: false
      t.jsonb :scope, null: false, default: {}
      # Lower runs first.
      t.integer :priority, null: false, default: 100
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at, null: false, default: -> { "now()" }
      t.integer :records_count
      t.string :last_error
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :ingestion_units, [ :feed, :kind, :key ], unique: true
    add_index :ingestion_units, [ :feed, :priority, :next_attempt_at ], where: "status = 'pending'",
      name: "index_ingestion_units_on_next_pending"

    # One row per feed: what the UI and the agent read to judge freshness.
    create_table :feed_statuses do |t|
      t.string :feed, null: false
      t.datetime :last_success_at
      t.datetime :last_failure_at
      t.string :last_error
      # Most recent observation or weather hour held for this feed.
      t.datetime :latest_data_at
      t.integer :remaining_quota
      # Set when the source asks us to back off (quota exhausted); no unit of
      # this feed runs before that time.
      t.datetime :paused_until
      t.timestamps
    end
    add_index :feed_statuses, :feed, unique: true

    # Raw API responses, kept for a month so normalisation can be replayed
    # without calling the source again.
    create_table :raw_payloads, id: false do |t|
      t.datetime :fetched_at, null: false
      t.string :feed, null: false
      t.string :path, null: false
      t.integer :status
      t.jsonb :body
    end
    execute "SELECT create_hypertable('raw_payloads', by_range('fetched_at', INTERVAL '7 days'))"
    add_index :raw_payloads, [ :feed, :path, :fetched_at ]
    execute "SELECT add_retention_policy('raw_payloads', INTERVAL '30 days')"
  end

  def down
    drop_table :raw_payloads
    drop_table :feed_statuses
    drop_table :ingestion_units
  end
end
