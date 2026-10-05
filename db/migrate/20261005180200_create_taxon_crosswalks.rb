class CreateTaxonCrosswalks < ActiveRecord::Migration[8.1]
  def change
    # Maps another source's taxon (iNaturalist, GBIF) onto the canonical one.
    # taxon_id stays null when no match was found, so misses remain visible.
    create_table :taxon_crosswalks do |t|
      t.string :source, null: false
      t.string :source_taxon_id, null: false
      t.string :source_name
      t.string :source_rank
      t.references :taxon, foreign_key: true
      t.string :match_method, null: false
      t.timestamps
    end

    add_index :taxon_crosswalks, [ :source, :source_taxon_id ], unique: true
  end
end
