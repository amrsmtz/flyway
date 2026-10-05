module Agent
  module Tools
    class SpeciesChanges < Base
      description "Species reported in a place during a period that were not reported in an earlier period (arrivals), " \
                  "and the reverse (departures). By default the earlier period is the same number of days just before."
      parameter :place, description: "Place name as the user wrote it"
      parameter :date_from, description: "First day of the later period, ISO format YYYY-MM-DD"
      parameter :date_to, description: "Last day of the later period, ISO format YYYY-MM-DD"
      parameter :earlier_from, description: "First day of the earlier period, if not the days just before", required: false
      parameter :earlier_to, description: "Last day of the earlier period", required: false

      def name = "species_changes"

      private

      def analyse(place:, period:, earlier_from: nil, earlier_to: nil)
        Analytics::Tools::SpeciesTurnover.new(place: place, period: period, earlier: optional_period(earlier_from, earlier_to)).call
      end
    end
  end
end
