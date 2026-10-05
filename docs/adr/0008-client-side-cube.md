# 8. The year sent once to the browser, on H3 cells

## Context

The timeline must scrub smoothly over twelve months. A request per step cannot do that over a network.

## Decision

- Send the whole year once as two compact "cubes": for each day, the cells with records and their counts per
  source and group; for each night, the wind at each grid point. About 100 KB and 90 KB compressed.
- The browser sums one or seven days and updates map feature states; a step costs about 0.1 ms and no request.
- Cells are **H3 hexagons**: resolution 4 (about 1,800 km²) for the overview and resolution 5 (about 250 km²)
  when zoomed in, loaded on demand. The cell is a generated column on each observation, stored as a bigint.
- The cubes are built from a continuous aggregate and cached for ten minutes.

## Alternatives considered

- **A fixed latitude and longitude grid.** Simpler, but cells shrink toward the north and do not nest.
- **Vector tiles per day.** The right answer at national scale; hundreds of tile sets for one year here.
- **Server-rendered frames.** No smoothness, and a load on the server for every viewer.

## Consequences

- The first load carries the year; after that the map works offline from the server's point of view.
- Positions that iNaturalist obscures (about 20 km) are left off the map: they are coarser than a cell.
- The map library and its styles are vendored; if the basemap host is blocked, data is drawn on a plain
  background.
- Hourly weather is stored but the map shows one wind per night; an hourly animation was cut for time.
