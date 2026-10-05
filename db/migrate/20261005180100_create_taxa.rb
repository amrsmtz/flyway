class CreateTaxa < ActiveRecord::Migration[8.1]
  def change
    # Canonical taxonomy: one row per eBird/Clements taxon.
    create_table :taxa do |t|
      t.string :species_code, null: false
      t.string :scientific_name, null: false
      t.string :common_name, null: false
      t.string :category, null: false
      t.decimal :taxon_order, precision: 10, scale: 2
      t.string :order_name
      t.string :family_code
      t.string :family_scientific_name
      t.string :family_common_name
      t.boolean :extinct, null: false, default: false
      # eBird's own roll-up target (subspecies and forms report as a species).
      t.string :report_as_code
      t.references :parent_species, foreign_key: { to_table: :taxa }
      t.references :species_group, foreign_key: true
      t.string :taxonomy_version, null: false
      t.timestamps
    end

    add_index :taxa, :species_code, unique: true
    add_index :taxa, "lower(scientific_name)", name: "index_taxa_on_lower_scientific_name"
    add_index :taxa, :family_code
    add_index :taxa, :category
  end
end
