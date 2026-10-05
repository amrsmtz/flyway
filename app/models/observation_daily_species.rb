# Continuous aggregate: observations per day, source, area and species.
class ObservationDailySpecies < ApplicationRecord
  self.table_name = "observation_daily_species"

  belongs_to :species, class_name: "Taxon"

  def readonly?
    true
  end
end
