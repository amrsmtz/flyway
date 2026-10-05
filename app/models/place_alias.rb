class PlaceAlias < ApplicationRecord
  belongs_to :place

  validates :name, :normalized_name, presence: true

  # Lower-case, accent-free, punctuation-free form used for matching.
  def self.normalize(name)
    name.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase.gsub(/[^a-z0-9]+/, " ").strip
  end
end
