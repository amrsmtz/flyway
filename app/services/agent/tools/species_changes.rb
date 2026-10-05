module Agent
  module Tools
    class SpeciesChanges < Base
      description "Species reported in a place during a period that were not reported in an earlier period (arrivals), " \
                  "and the reverse (departures). By default the earlier period is the same number of days just before."
      param :place, desc: "Place name as the user wrote it"
      param :date_from, desc: "First day of the later period, ISO format YYYY-MM-DD"
      param :date_to, desc: "Last day of the later period, ISO format YYYY-MM-DD"
      param :earlier_from, desc: "First day of the earlier period, if not the days just before", required: false
      param :earlier_to, desc: "Last day of the earlier period", required: false

      def name = "species_changes"

      private

      def analyse(place:, period:, earlier_from: nil, earlier_to: nil)
        Analytics::Tools::SpeciesTurnover.new(place: place, period: period, earlier: optional_period(earlier_from, earlier_to)).call
      end
    end
  end
end
