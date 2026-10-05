class Taxon < ApplicationRecord
  # eBird categories. Only "species" rows count toward species-level metrics;
  # subspecies and forms roll up through parent_species.
  CATEGORIES = %w[species issf form intergrade domestic hybrid slash spuh].freeze

  belongs_to :parent_species, class_name: "Taxon", optional: true
  belongs_to :species_group, optional: true
  has_many :crosswalks, class_name: "TaxonCrosswalk", dependent: :nullify

  validates :species_code, :scientific_name, :common_name, :taxonomy_version, presence: true
  validates :category, inclusion: { in: CATEGORIES }

  scope :species, -> { where(category: "species") }

  # The species this taxon counts as, or nil for hybrids, slashes and spuhs.
  def canonical_species
    return self if category == "species"

    parent_species
  end
end
