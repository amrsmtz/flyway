# The agent's language model. The provider and models are configuration:
# AGENT_PROVIDER and AGENT_MODELS (comma-separated, tried in order) can point
# the agent at another vendor without touching the code, given its API key.
RubyLLM.configure do |config|
  config.gemini_api_key = Rails.application.credentials.dig(:gemini, :api_key)
  config.openai_api_key = Rails.application.credentials.dig(:openai, :api_key)
  config.anthropic_api_key = Rails.application.credentials.dig(:anthropic, :api_key)
  # A question must feel interactive: fail fast and fall back instead of waiting.
  config.request_timeout = 20
  config.max_retries = 1
end

Rails.application.config.x.agent.provider = ENV.fetch("AGENT_PROVIDER", "gemini").to_sym
Rails.application.config.x.agent.models = ENV.fetch("AGENT_MODELS", "gemini-3.5-flash-lite,gemini-3.6-flash").split(",")
