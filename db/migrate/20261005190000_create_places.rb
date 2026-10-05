class CreatePlaces < ActiveRecord::Migration[8.1]
  def change
    # Gazetteer: every location a question can refer to.
    create_table :places do |t|
      t.string :kind, null: false
      t.string :name, null: false
      t.string :province_code
      t.references :parent, foreign_key: { to_table: :places }
      # eBird region code (CA-QC, CA-QC-MR) or hotspot id (L123456).
      t.string :ebird_code
      t.integer :inaturalist_place_id
      t.float :latitude, null: false
      t.float :longitude, null: false
      # Bounding box for areas; null for point-like places.
      t.float :min_latitude
      t.float :min_longitude
      t.float :max_latitude
      t.float :max_longitude
      # Radius used to gather nearby observations when the place is a point.
      t.float :default_radius_km
      t.boolean :featured, null: false, default: false
      # Ranks candidates of the same kind (checklists for hotspots, population for cities).
      t.integer :importance, null: false, default: 0
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end

    add_index :places, :ebird_code, unique: true
    add_index :places, :kind
    add_index :places, :province_code
    add_index :places, :featured, where: "featured"
    # Distance searches use this expression (see Place::LOCATION_SQL) rather
    # than a geography column, which Active Record cannot map to a type.
    add_index :places, "(ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography)",
      using: :gist, name: "index_places_on_location"
  end
end
