class CreatePlaceAliases < ActiveRecord::Migration[8.1]
  def change
    # Names a place can be searched by. normalized_name is lower-case,
    # accent-free and punctuation-free, so "Cap-Tourmente" and
    # "cap tourmente" compare equal.
    create_table :place_aliases do |t|
      t.references :place, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.timestamps
    end

    add_index :place_aliases, [ :place_id, :normalized_name ], unique: true
    add_index :place_aliases, :normalized_name, using: :gin, opclass: :gin_trgm_ops,
      name: "index_place_aliases_on_normalized_name_trgm"
  end
end
