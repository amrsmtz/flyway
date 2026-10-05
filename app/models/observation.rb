class Observation < ApplicationRecord
  UNIQUE_KEY = %i[source source_id observed_at].freeze
  SOURCES = %w[ebird inaturalist].freeze
  BASES = %w[checklist region_day record].freeze
  # confirmed:  reviewed and accepted (eBird reviewer, iNaturalist research grade)
  # unreviewed: plausible but not individually checked (eBird within regional
  #             filters, iNaturalist needs ID)
  # flagged:    held for review or rejected by the source
  # casual:     iNaturalist records that cannot reach research grade
  QUALITY_TIERS = %w[confirmed unreviewed flagged casual].freeze

  belongs_to :taxon, optional: true
  belongs_to :species, class_name: "Taxon", optional: true
  belongs_to :species_group, optional: true

  def source_url
    case source
    when "ebird" then "https://ebird.org/checklist/#{checklist_source_id}" if checklist_source_id
    when "inaturalist" then "https://www.inaturalist.org/observations/#{source_id}"
    end
  end
end
