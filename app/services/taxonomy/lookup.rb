module Taxonomy
  # In-memory index of the canonical taxonomy by eBird species code, for
  # normalising thousands of observations without a query each.
  class Lookup
    Entry = Data.define(:taxon_id, :species_id, :species_group_id)

    def initialize
      @by_code = Taxon.pluck(:species_code, :id, :category, :parent_species_id, :species_group_id)
                      .to_h do |code, id, category, parent_species_id, species_group_id|
        species_id = category == "species" ? id : parent_species_id
        [ code, Entry.new(taxon_id: id, species_id: species_id, species_group_id: species_group_id) ]
      end
    end

    # Nil when the code is unknown to our copy of the taxonomy.
    def by_species_code(code)
      @by_code[code]
    end
  end
end
