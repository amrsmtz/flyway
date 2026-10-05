module Agent
  # What one question accumulates while tools run: the full results, the
  # evidence sets (given keys E1, E2... for citations) and how each place
  # name was understood.
  class Run
    MAX_TOOL_CALLS = 5

    attr_reader :tool_results, :evidence

    def initialize
      @tool_results = []
      @evidence = []
    end

    def budget_left?
      @tool_results.size < MAX_TOOL_CALLS
    end

    # Stores the full result and returns the compact version for the model:
    # evidence reduced to keys and titles.
    def record(tool:, arguments:, result:, place: nil)
      keyed = result.fetch(:evidence, []).map do |evidence_set|
        evidence_set.merge(key: "E#{@evidence.size + 1}", tool: tool).tap { |set| @evidence << set }
      end

      @tool_results << { tool: tool, arguments: arguments, place: place, result: result.except(:evidence) }
      result.except(:evidence).merge(place_understood_as: place, evidence: keyed.map { |set| set.slice(:key, :title) }).compact
    end

    def record_error(tool:, arguments:, message:)
      @tool_results << { tool: tool, arguments: arguments, error: message }
      { error: message }
    end

    def flags
      @tool_results.flat_map { |entry| entry.dig(:result, :flags).to_a }.uniq { |flag| flag[:code] }
    end

    def errors
      @tool_results.filter_map { |entry| entry[:error] }
    end

    def tools_used
      @tool_results.reject { |entry| entry[:error] }.pluck(:tool).uniq
    end
  end
end
