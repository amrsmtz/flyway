# 9. Migrations as the schema's source of truth

## Context

Rails records the schema in `schema.rb`, which cannot express hypertables, continuous aggregates, retention and
compression policies or generated H3 columns. The SQL alternative, `structure.sql`, needs a `pg_dump` matching
the server (PostgreSQL 17) on every developer machine and in CI.

## Decision

Do not dump or load a schema file. A database is always built by replaying the migrations, which CI does on
every push against the same TimescaleDB image as production.

## Consequences

- One description of the schema, exercised constantly, with nothing to keep in sync.
- Building a fresh database gets slower as migrations accumulate; with fifteen it takes a second.
- Tests cannot use `db:test:prepare`; the test database is migrated explicitly.
- Old migrations must keep working, so they are not edited once deployed.
