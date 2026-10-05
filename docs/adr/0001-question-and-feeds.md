# 1. The question and the three feeds

## Context

The brief asks for a question about the physical and natural world, answered from at least three real-time
feeds, with history to replay. The question has to be defensible, and the feeds have to genuinely need each
other.

## Decision

Ask how night weather relates to bird migration in eastern Canada, using:

- **eBird** for structured birding effort (checklists),
- **iNaturalist** for an independent stream of photographed observations covering the whole region,
- **Open-Meteo** for hourly weather, including wind at the height birds fly.

Three groups are featured because they migrate differently: warblers (night migrants, sensitive to wind),
raptors (day migrants that concentrate at Tadoussac) and Snow Goose (stages in huge flocks at Cap Tourmente).

## Alternatives considered

- **ECCC GeoMet for weather.** More authoritative for Canada, but many datasets and formats to assemble.
  Open-Meteo gives one uniform API with altitude winds and a year of history.
- **GBIF as a third biodiversity feed.** It republishes eBird and iNaturalist with days of delay, so it adds
  deduplication work and little new information inside a 12-month window. It was the stretch goal and was cut.
- **Movebank GPS tracks.** Few public, live tracks in the region.
- **Other questions** (wildfire smoke, river levels). Their feeds are cleaner; the difficulty of honest
  observation data is what made this one worth doing.

## Consequences

- The link between weather and observations is noisy and indirect: observers see birds after they land, hours
  after the flight. The system therefore describes associations and says so.
- Two of the three feeds are citizen science, so observer effort is the central modelling problem (ADR 6).
- The direct measure of nocturnal migration, weather radar, is left as the main future step.
