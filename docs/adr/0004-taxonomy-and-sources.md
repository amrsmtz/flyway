# 4. One canonical taxonomy, sources never merged

## Context

eBird and iNaturalist name and split species differently, record at different levels (subspecies, species,
genus) and many people post the same sighting to both, with no shared identifier.

## Decision

- **eBird/Clements is the canonical taxonomy** (17,891 taxa). The project is about birds only and eBird's
  taxonomy carries the roll-up from subspecies to species.
- **iNaturalist taxa are matched by scientific name**, subspecies unknown to eBird roll up to their species, and
  identifications above species level (a genus, a family) stay unmatched. Every decision is stored in
  `taxon_crosswalks`, misses included, and unmatched names are listed on the status page.
- **Records from different sources are never merged.** Figures are computed per source, and a tool compares the
  sources instead of blending them.

## Alternatives considered

- **GBIF backbone as the canonical taxonomy.** The right choice for a multi-taxon system; unnecessary here.
- **Fuzzy matching of duplicates** (same species, day, place and a similar observer name). It would produce a
  "combined count" that looks precise and is not.

## Consequences

- About 97% of iNaturalist taxa matched in testing; the rest are genus-level and higher identifications, which
  still count as observer effort.
- No single combined total exists. Where the sources differ, the answer says so and explains why: eBird lists
  everything seen or heard, iNaturalist what was photographed.
- A taxonomy update (Clements changes yearly) means re-importing taxa and re-running the crosswalk; the version
  is stored with each taxon.
