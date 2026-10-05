class CreateObservationTables < ActiveRecord::Migration[8.1]
  # H3 cell (resolution 6, about 36 km²) of a position, stored as a bigint
  # because Active Record has no type for h3index.
  H3_CELL = "h3_latlng_to_cell(point(longitude, latitude), 6)::bigint".freeze

  def up
    # An eBird checklist: one outing by one observer or group. Its effort
    # fields are what make "not reported" meaningful.
    create_table :checklists, id: false do |t|
      t.datetime :observed_at, null: false
      t.date :observed_on, null: false
      t.string :source, null: false
      t.string :source_id, null: false
      t.references :place
      # Featured site whose radius contains the checklist, if any.
      t.references :site
      t.string :location_code
      t.string :county_code
      t.string :province_code
      t.float :latitude, null: false
      t.float :longitude, null: false
      t.string :protocol
      t.float :duration_hours
      t.float :distance_km
      # True when the observer reported every species detected, so a species
      # missing from the list was looked for and not found.
      t.boolean :complete, null: false, default: false
      t.integer :observer_count
      t.integer :species_count
      # Shared checklists carry the same group id; count each group once.
      t.string :group_code
      t.datetime :source_created_at
      t.datetime :source_updated_at
      t.datetime :first_ingested_at, null: false, default: -> { "now()" }
    end
    execute "ALTER TABLE checklists ADD COLUMN h3_cell bigint GENERATED ALWAYS AS (#{H3_CELL}) STORED"
    execute "SELECT create_hypertable('checklists', by_range('observed_at', INTERVAL '1 month'))"
    add_index :checklists, [ :source, :source_id, :observed_at ], unique: true
    add_index :checklists, [ :site_id, :observed_at ]
    add_index :checklists, [ :county_code, :observed_at ]

    # One taxon seen at one place and time, from any feed.
    create_table :observations, id: false do |t|
      t.datetime :observed_at, null: false
      t.date :observed_on, null: false
      t.string :source, null: false
      t.string :source_id, null: false
      # checklist: a line of an eBird checklist. region_day: the single
      # record per species that eBird returns for a county and day.
      # record: a stand-alone observation (iNaturalist).
      t.string :basis, null: false
      t.references :taxon
      # Denormalised from taxa: the species the taxon counts as, and its
      # featured group, so aggregates need no join.
      t.references :species
      t.references :species_group
      t.string :checklist_source_id
      t.string :county_code
      t.string :province_code
      t.float :latitude, null: false
      t.float :longitude, null: false
      t.integer :individual_count
      # confirmed, unreviewed, flagged or casual; see Observation::QUALITY_TIERS.
      t.string :quality_tier, null: false
      t.boolean :obscured, null: false, default: false
      t.integer :positional_accuracy_m
      t.jsonb :details, null: false, default: {}
      t.datetime :source_updated_at
      t.datetime :first_ingested_at, null: false, default: -> { "now()" }
    end
    execute "ALTER TABLE observations ADD COLUMN h3_cell bigint GENERATED ALWAYS AS (#{H3_CELL}) STORED"
    execute "SELECT create_hypertable('observations', by_range('observed_at', INTERVAL '1 month'))"
    add_index :observations, [ :source, :source_id, :observed_at ], unique: true
    add_index :observations, [ :species_id, :observed_at ]
    add_index :observations, [ :county_code, :observed_at ]
    add_index :observations, [ :h3_cell, :observed_at ]

    # What a source says happened in a county on a day: the denominator of
    # every effort-normalised figure, and the yardstick for our own coverage.
    create_table :region_day_efforts, id: false do |t|
      t.date :day, null: false
      t.string :source, null: false
      t.string :county_code, null: false
      t.integer :checklist_count, null: false
      t.integer :observer_count
      t.integer :species_count
      t.datetime :fetched_at, null: false
    end
    execute "SELECT create_hypertable('region_day_efforts', by_range('day', INTERVAL '3 months'))"
    add_index :region_day_efforts, [ :source, :county_code, :day ], unique: true
  end

  def down
    drop_table :region_day_efforts
    drop_table :observations
    drop_table :checklists
  end
end
