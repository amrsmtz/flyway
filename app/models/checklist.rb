class Checklist < ApplicationRecord
  UNIQUE_KEY = %i[source source_id observed_at].freeze

  belongs_to :place, optional: true
  belongs_to :site, class_name: "Place", optional: true

  scope :complete, -> { where(complete: true) }

  def source_url
    "https://ebird.org/checklist/#{source_id}" if source == "ebird"
  end
end
