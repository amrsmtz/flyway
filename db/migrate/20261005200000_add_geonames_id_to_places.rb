class AddGeonamesIdToPlaces < ActiveRecord::Migration[8.1]
  def change
    add_column :places, :geonames_id, :integer
    add_index :places, :geonames_id, unique: true
  end
end
