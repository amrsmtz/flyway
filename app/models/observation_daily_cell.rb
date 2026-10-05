# Continuous aggregate: observations per day, source, H3 cell (resolution 5)
# and featured group. Feeds the map.
class ObservationDailyCell < ApplicationRecord
  def readonly?
    true
  end
end
