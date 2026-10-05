# Five-minute demo

Open https://168-138-92-191.sslip.io on a wide screen. Times are cumulative.

## 0:00 — The question (30 s)

> "Every spring and fall, hundreds of millions of birds cross eastern Canada, mostly at night. Whether they move
> depends on the wind. Flyway asks: did the weather move the birds, and how sure can we be?"

Point at the three dots in the header: eBird, iNaturalist, Open-Meteo. "Three live feeds, each with its own
delay and its own idea of quality. Green means collected on time."

## 0:30 — Ask a question (60 s)

Click **"Did last night's north winds bring more warblers to Tadoussac?"**

Read the first sentence aloud. If the wind was not from the north, the agent says the premise is wrong: "It
does not go along with the question; it checks."

Point at, in order:

- the **key figures**, each with an evidence link;
- the **confidence** badge and its reasons: "Computed by the server from the data, not chosen by the model";
- **data freshness** at the bottom.

## 1:30 — Follow the evidence (45 s)

Click **[E1]**. "How the figure was obtained, and the records behind it." Click **Open original** on one row to
land on Open-Meteo, an eBird checklist or an iNaturalist observation. "Every number goes back to its source."

## 2:15 — Replay the year (75 s)

Back on the map, click **Show on map**, then **Zoom to All**.

- Choose **Warblers**. "Colour is the share of bird records that are warblers, so a busy city is not darker
  just because more people live there."
- Drag the timeline to mid-May, then to September. "Twelve months, no request to the server while scrubbing."
- Press **Play** for a few seconds. Point at the arrows: "Night wind at 750 metres, where songbirds fly." Point
  at the strip under the bars: "Green nights pushed birds along; red nights held them back."
- Zoom into Montreal: the hexagons become finer.

## 3:30 — What the data cannot say (45 s)

Click **"Which areas have too few observations to draw any conclusion?"**

"Grey cells have too few records to tell. Where there is no cell, nobody reported anything: that is not the
same as no birds. The agent keeps those apart, and so does the map."

## 4:15 — Behind it (30 s)

Open **Data status**. "Collection progress per feed, the eBird quota, what failed, which names could not be
matched. eBird allows 500 requests an hour, so the queue collects the most useful days first; this page shows
what is held and what is not."

"Storage is TimescaleDB, new to me: hypertables, continuous aggregates that absorb late data, compression."

## 4:45 — Limits and next step (15 s)

"Observers see birds after they land. The real next step is weather radar, which sees them in flight."

---

## If something goes wrong

- **The model does not answer.** The four suggested questions are answered ahead of time and still display.
  Say so: it is a design choice for a free model tier.
- **The basemap is blank.** The data still draws on a plain background; the map tiles come from a third party.
- **The site is unreachable from the room's network.** Some corporate filters block the `sslip.io` host name.
  Use a phone connection.
- **A feed shows "late".** Open the status page and show the last problem; that is what the page is for.

## Questions that show the agent well

- "Is there a migration wave in southern Quebec right now, and is the weather favourable?"
- "Compare this fall's snow goose migration at Cap Tourmente with last spring's."
- "Which species arrived around Montreal this week that were not reported last week?"
- "Where do eBird and iNaturalist disagree on what is being seen this week?"
- "Any raptors near Tadousac lately?" (a misspelt place, matched and mentioned)
- "What is the capital of France?" (declined)
