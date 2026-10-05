module Agent
  module Tools
    class ObservationCoverage < Base
      description "Where there are too few observations to conclude anything, inside a province or region over a period: " \
                  "areas that are usually watched but have few or no records now."
      parameter :place, description: "Province or region name as the user wrote it; 'eastern Canada' for everything"
      parameter :date_from, description: "First day, ISO format YYYY-MM-DD"
      parameter :date_to, description: "Last day, ISO format YYYY-MM-DD"

      def name = "observation_coverage"

      private

      def analyse(place:, period:)
        Analytics::Tools::CoverageReport.new(place: place, period: period).call
      end
    end
  end
end
