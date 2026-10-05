# Continuous aggregate: one row per weather point and night (local noon to
# noon), with wind averaged over the hours of darkness.
class WeatherNight < ApplicationRecord
  include WindVector

  belongs_to :weather_point

  def readonly?
    true
  end

  # Calendar date on which the night begins.
  def starts_on
    night.in_time_zone("America/Toronto").to_date
  end
end
