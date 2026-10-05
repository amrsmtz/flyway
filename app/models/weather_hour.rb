class WeatherHour < ApplicationRecord
  UNIQUE_KEY = %i[weather_point_id time].freeze

  belongs_to :weather_point
end
