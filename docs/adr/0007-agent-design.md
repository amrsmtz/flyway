# 7. An agent that neither computes nor judges

## Context

The agent must be reliable and grounded, run on a free model tier, and feel interactive. Small, fast models
choose tools well and write plain sentences, but invent figures and forget caveats when left to.

## Decision

- **Five coarse tools**, one per kind of question, each returning figures, ready-to-quote strings such as
  "62% (5 of 8 complete checklists)", flags and evidence. The model does not write SQL.
- **Place names go to tools as text** and are resolved in the gazetteer inside the tool, so the model can call
  all tools in one turn: two model calls per question.
- **Structured output**: a direct answer, key figures with evidence keys, caveats, and a "cannot answer" flag.
- **A validator** drops citations to unknown evidence and lists numbers that are not in the tool results.
- **Confidence and freshness are computed by the server** from tool flags and feed health.
- **Quota protection**: cached answers, suggested questions answered ahead of time, rate limits, a fallback
  model, and the last good answer when no model answers.

## Alternatives considered

- **Text-to-SQL.** Flexible, but every metric would be redefined per question, effort normalisation would be
  optional, and results could not be traced to stored evidence.
- **Many small tools with several turns.** More model calls per question, slower, and more quota.
- **A second model as a judge.** Doubles the calls; the validator checks what can be checked without one.
- **Letting the model state its confidence.** Not reproducible, and a model is rarely unsure of its own text.

## What testing taught

- The model corrected a false premise by itself ("last night's north winds" when the wind was south-south-west).
- It once produced a figure by subtracting two others; the validator flagged it, and the tool now supplies it.
- It interpreted "last night" as different date ranges on different runs, so the prompt fixes relative dates.
- The largest model listed for the key answered "service unavailable" on every attempt; the lite model was
  fast and reliable, so it became the primary and a mid-size one the fallback.
- The free tier is limited per minute, not only per day: 5 requests for the fallback model, and the primary
  refused after about 18. Running the test questions back to back exhausted both. The app now caps new
  questions at six a minute overall.
- A failed attempt on one model used to leave its tool results, and its used-up tool budget, to the next model;
  each attempt now starts clean.

## Consequences

- The agent cannot answer questions outside its five tools; it says so rather than improvise.
- Wrong reasoning over correct figures is still possible and is not caught by the validator.
- Changing provider is configuration (`AGENT_PROVIDER`, `AGENT_MODELS`), through RubyLLM.
