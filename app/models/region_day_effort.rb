class RegionDayEffort < ApplicationRecord
  UNIQUE_KEY = %i[source county_code day].freeze
end
