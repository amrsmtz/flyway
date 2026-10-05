class AddSlugToPlaces < ActiveRecord::Migration[8.1]
  def change
    # Stable key for hand-curated sites and regions (config/gazetteer.yml).
    add_column :places, :slug, :string
    add_index :places, :slug, unique: true
  end
end
