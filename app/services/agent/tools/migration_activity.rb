module Agent
  module Tools
    class MigrationActivity < Base
      description "How much a species group (or all birds) is being reported in a place over a period, normalised by " \
                  "observer effort, compared with another period (by default the same number of days just before). " \
                  "Use it for 'is there a wave', 'more or fewer than', and to compare two periods or seasons."
      parameter :place, description: "Place name as the user wrote it (city, region, province or birding site)"
      parameter :date_from, description: "First day, ISO format YYYY-MM-DD"
      parameter :date_to, description: "Last day, ISO format YYYY-MM-DD"
      parameter :group, description: GROUPS_HINT, required: false
      parameter :compare_from, description: "First day of the comparison period, if not the days just before", required: false
      parameter :compare_to, description: "Last day of the comparison period", required: false

      def name = "migration_activity"

      private

      def analyse(place:, period:, group: nil, compare_from: nil, compare_to: nil)
        Analytics::Tools::MigrationSnapshot.new(place: place, period: period, group: group(group),
                                                comparison: optional_period(compare_from, compare_to)).call
      end
    end
  end
end
