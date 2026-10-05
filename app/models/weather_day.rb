# Continuous aggregate: daily means per weather point.
class WeatherDay < ApplicationRecord
  include WindVector

  belongs_to :weather_point

  def readonly?
    true
  end
end
