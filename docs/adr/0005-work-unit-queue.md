# 5. A work-unit queue for ingestion

## Context

Three feeds must be backfilled over twelve months and then kept current, under different rate limits, on a
single small machine, and survive deployments and failures part-way.

## Decision

One table, `ingestion_units`, holds every unit of work for every feed: a county and day, a checklist, a day of
observations, a month of weather for ten points. Each has a priority, a status, an attempt count and a next
attempt time.

- A recurring job per feed runs `Ingestion::Runner` for under a minute: it claims the most urgent due unit with
  `FOR UPDATE SKIP LOCKED`, runs its handler and records the result.
- Unavailable source: retry after 2, 4, 8, 16 minutes, then mark the unit *dead*. Quota exhausted: postpone the
  unit without counting an attempt and pause the feed.
- Handlers upsert on the source's identifier, so a unit can always be run again.
- Live data uses the same mechanism: a finished unit is sent back to the queue when its result is older than a
  refresh interval.

## Alternatives considered

- **One long-running backfill script per feed.** Simple until it is interrupted.
- **One background job per unit.** Solid Queue would hold tens of thousands of jobs whose ordering and progress
  are hard to see or change. Reordering the eBird backfill was a single `UPDATE` on the unit table.
- **Kafka or another log.** Right for true streams at volume; far more than three polled APIs need.

## Consequences

- Backfill progress, failures and coverage are plain rows, shown on the status page.
- Jobs run in their own container, so a long backfill does not slow the web server.
- Throughput is bounded by one runner per feed, which is the polite rate for these APIs anyway.
