module Agent
  # Answers the suggested questions ahead of time, so visitors get them at
  # once and without using the model's quota.
  class RefreshSuggestedJob < ApplicationJob
    def perform
      AgentAnswer::SUGGESTED.each { |question| Responder.new.refresh(question) }
    end
  end
end
