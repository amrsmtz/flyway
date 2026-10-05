module Inaturalist
  # Reconciles iNaturalist taxa with the canonical (eBird) taxonomy and
  # remembers every decision in taxon_crosswalks, including failures, so
  # unmatched taxa can be reviewed rather than silently dropped.
  class TaxonMatcher
    SOURCE = "inaturalist".freeze
    # Ranks below species: matched on their own name, else rolled up.
    INFRASPECIFIC_RANKS = %w[subspecies variety form hybrid].freeze
    Match = Data.define(:taxon_id, :species_id, :species_group_id)
    NO_MATCH = Match.new(taxon_id: nil, species_id: nil, species_group_id: nil)

    def initialize
      @matches = {}
      @canonical = Taxon.pluck(:id, :scientific_name, :category, :parent_species_id, :species_group_id)
                        .to_h { |id, name, *rest| [ name.downcase, [ id, *rest ] ] }
      TaxonCrosswalk.where(source: SOURCE).where.not(taxon_id: nil).pluck(:source_taxon_id, :taxon_id).each do |source_id, taxon_id|
        @matches[source_id] = match_for(Taxon.find(taxon_id))
      end
      TaxonCrosswalk.where(source: SOURCE, taxon_id: nil).pluck(:source_taxon_id).each { |id| @matches[id] = NO_MATCH }
    end

    # taxon is the "taxon" object of an iNaturalist observation, or nil.
    def match(taxon)
      return NO_MATCH if taxon.nil?

      @matches[taxon.fetch("id").to_s] ||= resolve(taxon)
    end

    private

    def resolve(taxon)
      name = taxon.fetch("name")
      canonical, method = find_canonical(name, taxon["rank"])

      TaxonCrosswalk.upsert(
        { source: SOURCE, source_taxon_id: taxon.fetch("id").to_s, source_name: name, source_rank: taxon["rank"],
          taxon_id: canonical&.first, match_method: method },
        unique_by: %i[source source_taxon_id]
      )
      canonical ? build_match(*canonical) : NO_MATCH
    end

    # Exact scientific name first; a subspecies unknown to eBird counts as
    # its species. Genus-level and higher identifications stay unmatched.
    def find_canonical(name, rank)
      exact = @canonical[name.downcase]
      return [ exact, "exact_name" ] if exact

      if INFRASPECIFIC_RANKS.include?(rank)
        species = @canonical[name.split.first(2).join(" ").downcase]
        return [ species, "rollup" ] if species
      end

      [ nil, "unmatched" ]
    end

    def build_match(id, category, parent_species_id, species_group_id)
      Match.new(taxon_id: id, species_id: category == "species" ? id : parent_species_id, species_group_id: species_group_id)
    end

    def match_for(taxon)
      build_match(taxon.id, taxon.category, taxon.parent_species_id, taxon.species_group_id)
    end
  end
end
