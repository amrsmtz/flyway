module Agent
  module Tools
    class SourceComparison < Base
      description "Compares what eBird and iNaturalist report in a place over a period: species on both, species on only " \
                  "one, and how much each source observed. Use it for questions about the sources disagreeing."
      param :place, desc: "Place name as the user wrote it"
      param :date_from, desc: "First day, ISO format YYYY-MM-DD"
      param :date_to, desc: "Last day, ISO format YYYY-MM-DD"

      def name = "source_comparison"

      private

      def analyse(place:, period:)
        Analytics::Tools::SourceAgreement.new(place: place, period: period).call
      end
    end
  end
end
