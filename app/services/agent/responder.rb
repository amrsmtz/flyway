module Agent
  # Returns the answer to show for a question: a fresh cached one when
  # there is one, otherwise a new one from the model. When the model cannot
  # be reached, the last good answer to the same question is shown instead.
  class Responder
    def call(question)
      AgentAnswer.fresh_for(question) || ask(question)
    end

    # Used by the recurring job: always asks again.
    def refresh(question)
      ask(question)
    end

    private

    def ask(question)
      return limit_reached(question) if AgentAnswer.daily_limit_reached?

      answer = Orchestrator.new.call(question)
      answer.save!
      answer.status == "failed" ? AgentAnswer.latest_for(question) || answer : answer
    end

    def limit_reached(question)
      AgentAnswer.latest_for(question) ||
        AgentAnswer.new(question: question, question_key: AgentAnswer.question_key_for(question), status: "failed",
                        error: "The daily limit of questions to the language model is reached.")
    end
  end
end
