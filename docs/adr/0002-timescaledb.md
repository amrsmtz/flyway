# 2. TimescaleDB for time-series storage

## Context

Observations and weather are time series that keep changing after the fact: checklists are uploaded days late,
eBird reviewers accept or reject records for weeks, iNaturalist identifications move. The timeline needs
per-day and per-night summaries over a year that reflect those late changes. The brief also asks for one
technology that is new to me.

## Decision

Run TimescaleDB inside the same PostgreSQL as the relational data, and use hypertables, continuous aggregates,
columnstore compression and a retention policy.

- Continuous aggregates refresh every 15 minutes **with no start offset**. Late data can land anywhere in the
  year; TimescaleDB tracks which buckets were invalidated and recomputes only those.
- Real-time aggregation is on, so today's buckets show before they are materialised.
- Observations are compressed after 60 days rather than a few, because they are still being edited.

## Alternatives considered

- **Plain PostgreSQL with materialised views.** Enough at this size, but a materialised view is refreshed
  whole, and late data makes that the common case.
- **ClickHouse or DuckDB.** Faster for analytics, but a second database to operate and keep consistent with
  places and taxa, for a volume that does not need it.

## What testing taught

- A continuous aggregate that combines a time zone with `offset` kills the backend on refresh in TimescaleDB
  2.30 (reproduced twice). A time zone with `origin` set to noon gives the same noon-to-noon "night" buckets.
- Compression keeps updates possible: an update inside a compressed chunk took about 10 ms locally. But a
  statement that looks for rows without bounding the time has to decompress every chunk. The iNaturalist update
  job did exactly that, hit TimescaleDB's limit of 100,000 decompressed tuples per transaction and stopped two
  hours after compression was switched on. The status page showed the feed as late; the job now bounds its
  search in time and the limit is lifted.
- The Apache-licensed edition offered by most managed PostgreSQL services has neither compression nor
  continuous aggregates, which decided the hosting (ADR 10).

## Consequences

- One database to deploy and back up, with joins between time series and reference data.
- `schema.rb` cannot describe any of this (ADR 9).
- At this volume the choice is about behaviour and headroom, not necessity; a reviewer is right to say plain
  PostgreSQL would have run it.
