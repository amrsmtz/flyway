module Taxonomy
  # Loads the eBird/Clements taxonomy as the canonical species list. Safe to
  # re-run: taxa are upserted on their eBird species code.
  class EbirdImporter
    BATCH_SIZE = 2_000

    def initialize(client: Ebird::Client.new)
      @client = client
    end

    def call
      version = latest_version
      rows = @client.taxonomy.map { |taxon| attributes_for(taxon, version) }

      Taxon.transaction do
        rows.each_slice(BATCH_SIZE) do |batch|
          Taxon.upsert_all(batch, unique_by: :species_code, update_only: batch.first.keys - %i[species_code])
        end
        link_parent_species
        SpeciesGroup.sync_definitions!
        assign_species_groups
      end

      { version: version, taxa: rows.size }
    end

    private

    def latest_version
      latest = @client.taxonomy_versions.find { |version| version["latest"] }
      latest.fetch("authorityVer").to_s
    end

    def attributes_for(taxon, version)
      {
        species_code: taxon.fetch("speciesCode"),
        scientific_name: taxon.fetch("sciName"),
        common_name: taxon.fetch("comName"),
        category: taxon.fetch("category"),
        taxon_order: taxon["taxonOrder"],
        order_name: taxon["order"],
        family_code: taxon["familyCode"],
        family_scientific_name: taxon["familySciName"],
        family_common_name: taxon["familyComName"],
        extinct: taxon["extinct"] == true,
        report_as_code: taxon["reportAs"],
        taxonomy_version: version
      }
    end

    def link_parent_species
      Taxon.connection.execute(<<~SQL)
        UPDATE taxa AS child
        SET parent_species_id = parent.id
        FROM taxa AS parent
        WHERE parent.species_code = child.report_as_code
          AND child.parent_species_id IS DISTINCT FROM parent.id
      SQL
      Taxon.where(report_as_code: nil).where.not(parent_species_id: nil).update_all(parent_species_id: nil)
    end

    # A taxon joins a group through its family, its own species code, or the
    # species it reports as. Hybrids and slashes across groups are left out.
    def assign_species_groups
      Taxon.connection.execute(<<~SQL)
        UPDATE taxa
        SET species_group_id = matched.group_id
        FROM (
          SELECT taxa.id AS taxon_id,
                 (SELECT species_groups.id
                  FROM species_groups
                  WHERE taxa.family_code = ANY (species_groups.family_codes)
                     OR taxa.species_code = ANY (species_groups.species_codes)
                     OR taxa.report_as_code = ANY (species_groups.species_codes)
                  ORDER BY species_groups.id
                  LIMIT 1) AS group_id
          FROM taxa
        ) AS matched
        WHERE taxa.id = matched.taxon_id
          AND taxa.species_group_id IS DISTINCT FROM matched.group_id
      SQL
    end
  end
end
