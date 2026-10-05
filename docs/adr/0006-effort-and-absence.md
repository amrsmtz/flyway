# 6. Effort normalisation and "nobody looked"

## Context

Citizen observations measure observers as much as birds: more are made at weekends, near cities and at famous
sites. A raw count rising can mean a migration wave or a sunny Saturday. And a place with no records may hold
no birds, or simply no observers.

## Decision

- **Never compare raw counts of a species or group.** A group is measured as its share of all bird records in
  the same place and period (iNaturalist), or as the share of complete checklists on which it appears (eBird
  reporting rate). Both stay stable when effort alone changes.
- **Test changes against chance** with a two-proportion test, and say whether a difference is larger than
  chance would often give.
- **Keep three states apart:** enough data, too little data (under 20 records or 5 complete checklists), and no
  data. On the map these are a coloured cell, a grey cell and no cell.
- **Only complete checklists support "not found".** The eBird flag saying the observer reported every species
  is stored and used as the condition.
- **Use eBird's own effort figures** per county and day as the denominator, and as the yardstick for how much
  of a day's checklists we hold.

## Alternatives considered

- **Observations per observer-hour.** The classic measure, but duration exists only on full checklists.
- **Occupancy or detection models.** The proper statistical treatment; not a three-day job and hard to explain
  to a non-specialist in two sentences.

## Consequences

- A share can fall because another group rose; answers quote both parts ("35 of 167 bird records").
- Thresholds are fixed and simple. They are conservative: the agent often says confidence is low, which is the
  honest outcome for a small site on a single day.
- iNaturalist's share is biased toward birds that are easy to photograph. That is stated when sources differ.
