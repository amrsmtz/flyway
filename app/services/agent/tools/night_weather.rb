module Agent
  module Tools
    class NightWeather < Base
      description "Night-by-night weather for a place: wind at the height where birds migrate, tailwind or headwind along " \
                  "the seasonal direction of travel, rain, pressure change, and whether each night was favourable for migration. " \
                  "A night is named by the evening it starts: 'last night' is the night of yesterday's date. " \
                  "With a group, also compares bird activity on mornings after favourable and unfavourable nights."
      parameter :place, description: "Place name as the user wrote it"
      parameter :date_from, description: "Evening of the first night, ISO format YYYY-MM-DD"
      parameter :date_to, description: "Evening of the last night, ISO format YYYY-MM-DD"
      parameter :group, description: GROUPS_HINT, required: false

      def name = "night_weather"

      private

      def analyse(place:, period:, group: nil)
        Analytics::Tools::WeatherContext.new(place: place, period: period, group: group(group)).call
      end
    end
  end
end
