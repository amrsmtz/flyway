class SpeciesGroup < ApplicationRecord
  # Featured groups shown in the UI. Membership is derived from the taxonomy.
  DEFINITIONS = [
    {
      key: "warblers",
      name: "Warblers",
      description: "New World warblers (family Parulidae), mostly night migrants.",
      family_codes: %w[paruli1],
      species_codes: []
    },
    {
      key: "snow_goose",
      name: "Snow Goose",
      description: "Snow Goose, which stages in large flocks along the St. Lawrence.",
      family_codes: [],
      species_codes: %w[snogoo]
    },
    {
      key: "raptors",
      name: "Raptors",
      description: "Hawks, eagles, falcons, Osprey and vultures, which migrate by day.",
      family_codes: %w[accipi1 falcon1 pandio1 cathar2],
      species_codes: []
    }
  ].freeze

  has_many :taxa, dependent: :nullify

  validates :key, :name, presence: true
  validates :key, uniqueness: true

  def self.sync_definitions!
    upsert_all(DEFINITIONS, unique_by: :key, update_only: %i[name description family_codes species_codes])
  end
end
