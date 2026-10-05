class AnswersController < ApplicationController
  MAX_QUESTION_LENGTH = 300

  # Protects the model's free-tier quota from a single eager visitor.
  rate_limit to: 8, within: 1.minute, only: :create, with: -> { render_busy }

  def create
    question = params[:question].to_s.squish.first(MAX_QUESTION_LENGTH)
    return render_frame("empty") if question.blank?

    @answer = Agent::Responder.new.call(question)
    render_frame("answer")
  end

  def show
    @answer = AgentAnswer.find(params[:id])
  end

  def evidence
    @answer = AgentAnswer.find(params[:id])
    @evidence = @answer.evidence_set(params[:key]) or raise ActiveRecord::RecordNotFound
  end

  private

  def render_frame(partial)
    render partial: "answers/#{partial}", locals: { answer: @answer }
  end

  def render_busy
    render partial: "answers/busy", status: :too_many_requests
  end
end
