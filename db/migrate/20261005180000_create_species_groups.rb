class CreateSpeciesGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :species_groups do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      # A taxon belongs to the group when its family or its species matches.
      t.string :family_codes, array: true, null: false, default: []
      t.string :species_codes, array: true, null: false, default: []
      t.timestamps
    end

    add_index :species_groups, :key, unique: true
  end
end
