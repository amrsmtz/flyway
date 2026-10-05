# 3. eBird ingestion under a 500-requests-per-hour quota

## Context

Measured on the first day:

- The API allows 500 requests per hour per key.
- For a region and day it returns one observation per species (the latest), not every checklist.
- A full checklist costs one request. On a fall Sunday the five provinces produced about 2,500 checklists;
  a spring Saturday is several times that.
- A province-level request times out; the county is the largest unit that answers.
- `product/stats` gives, per county and day, how many checklists and observers eBird received.

Twelve months for all 189 counties would take about eleven days of quota.

## Decision

Collect two things, for the 23 counties that contain the 22 featured sites:

1. **Per county and day, for twelve months:** eBird's own effort figures and one record per species with its
   review status.
2. **Full checklists near featured sites, for recent weeks:** these carry duration, distance and whether the
   list is complete, which is what a reporting rate needs.

A planner orders the queue by usefulness: live days, the migration seasons of the flagship sites, recent weeks,
other counties' seasons, then the rest of the year. Handlers stop 20 requests short of the quota and re-check
every 15 minutes, because the hourly window's start is not published.

## Alternatives considered

- **Every checklist in the region.** Affordable in fall for live data, not for history, and not in spring.
- **The eBird Basic Dataset** (monthly bulk file with every checklist). This is the right source for history. Access was
  requested on day one and did not arrive in time. It lags by weeks, so the API would still serve recent days.
- **Several API keys.** Against the spirit of the terms of use.

## Consequences

- True reporting rates exist only at featured sites and for recent weeks. Elsewhere eBird contributes presence
  and effort, and iNaturalist carries the regional picture.
- The status page shows, per county, how many days are held; an unheld day is treated as unknown.
- The order of the queue is a product decision. It was changed once the first night showed that full checklists
  were more numerous than estimated and were delaying the seasons a suggested question depends on.
