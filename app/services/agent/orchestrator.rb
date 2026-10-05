module Agent
  # Answers one question: lets the model pick tools, runs them, has the
  # model write the answer in a fixed structure, then checks that answer and
  # attaches freshness and confidence computed from the data.
  #
  # Two model calls per question (tool choice, then writing), which keeps
  # the agent inside a free-tier quota and the wait to a few seconds.
  class Orchestrator
    TOOLS = [ Tools::MigrationActivity, Tools::SpeciesChanges, Tools::NightWeather, Tools::SourceComparison,
              Tools::ObservationCoverage ].freeze
    ANSWER_SCHEMA = {
      type: "object",
      properties: {
        answer: { type: "string" },
        key_figures: {
          type: "array",
          items: { type: "object", properties: { text: { type: "string" }, evidence: { type: "array", items: { type: "string" } } },
                   required: %w[text evidence] }
        },
        caveats: { type: "array", items: { type: "string" } },
        cannot_answer: { type: "boolean" }
      },
      required: %w[answer key_figures caveats cannot_answer]
    }.freeze
    OFF_TOPIC = "I can only answer from the bird observations and weather I hold for eastern Canada. " \
                "Try asking about a place, a period and a group of birds.".freeze

    # Returns an unsaved AgentAnswer.
    def call(question)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      run, content, model = ask(question)
      build(question, run, content, model).tap { |answer| answer.duration_ms = elapsed_ms(started) }
    rescue RubyLLM::Error, Faraday::Error => e
      AgentAnswer.new(question: question, question_key: AgentAnswer.question_key_for(question), status: "failed",
                      error: "#{e.class}: #{e.message}".first(250), duration_ms: elapsed_ms(started))
    end

    private

    # Tries each configured model in turn; a model that is overloaded or
    # out of quota passes the question to the next one. Each attempt starts
    # a fresh run, so a failed attempt leaves no tool results or used-up
    # tool budget behind.
    def ask(question)
      models = Rails.configuration.x.agent.models
      models.each_with_index do |model, index|
        run = Run.new
        chat = RubyLLM.chat(model: model, provider: Rails.configuration.x.agent.provider, assume_model_exists: true)
                      .with_instructions(Prompt.new.to_s).with_temperature(0.2)
                      .with_tools(*TOOLS.map { |tool| tool.new(run) }).with_schema(ANSWER_SCHEMA)
        return [ run, chat.ask(question).content, model ]
      rescue RubyLLM::Error, Faraday::Error
        raise if index == models.size - 1
      end
    end

    def build(question, run, content, model)
      answer = content.is_a?(Hash) ? content.deep_stringify_keys : JSON.parse(content.to_s)
      # No successful tool call means nothing to ground an answer on.
      answer = { "answer" => OFF_TOPIC, "key_figures" => [], "caveats" => [], "cannot_answer" => true } if run.tools_used.empty?

      validator = Validator.new(answer: answer, run: run, question: question)
      unverified = validator.unverified_numbers
      freshness = Freshness.new(run.tools_used).to_a
      level, reasons = Confidence.new(run: run, freshness: freshness, unverified_numbers: unverified,
                                      cannot_answer: answer["cannot_answer"]).assess

      AgentAnswer.new(
        question: question, question_key: AgentAnswer.question_key_for(question),
        status: answer["cannot_answer"] ? "cannot_answer" : "answered",
        answer: validator.cleaned, tool_results: run.tool_results, evidence: run.evidence,
        confidence: level, confidence_reasons: reasons, freshness: freshness, unverified_numbers: unverified, model: model
      )
    rescue JSON::ParserError
      AgentAnswer.new(question: question, question_key: AgentAnswer.question_key_for(question), status: "failed",
                      error: "The model did not return a structured answer.", model: model)
    end

    def elapsed_ms(started)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    end
  end
end
