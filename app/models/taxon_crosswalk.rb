class TaxonCrosswalk < ApplicationRecord
  SOURCES = %w[inaturalist gbif].freeze
  MATCH_METHODS = %w[exact_name synonym rollup manual unmatched].freeze

  belongs_to :taxon, optional: true

  validates :source, inclusion: { in: SOURCES }
  validates :match_method, inclusion: { in: MATCH_METHODS }
  validates :source_taxon_id, presence: true, uniqueness: { scope: :source }

  scope :unmatched, -> { where(taxon_id: nil) }
end
