# Updating player headshots

Headshots are sourced from each team's own roster page and packed into
`assets/headshots.parquet` (one row per scraped player: `team_abbr`,
`scraped_name`, `player_id`, `content_type`, JPEG bytes). This doc describes
the full process to redo it -- e.g. once a season to pick up new signings,
updated photos, or to re-match players who had no ASA stats recorded yet.

The process has two halves:

1. **Scraping** (manual/agent-assisted, not automated) -- each team's
   roster page has a different site structure, so there's no stable scraper
   worth maintaining as code. Last time this was done with one AI agent per
   team scraping in parallel.
2. **Matching + compressing + packing** (automated) -- `scripts/update_headshots.R`.

## 1. Scraping

Roster pages (Spokane Zephyr FC dissolved -- skip):

| Team | Abbr | Roster URL |
|---|---|---|
| Fort Lauderdale United FC | `FTL` | https://www.ftlutd.com/womens/roster/ |
| Tampa Bay Sun FC | `TB` | https://www.tampabaysunfc.com/roster/ |
| Brooklyn FC | `BKN` | https://www.brooklynfootballclub.com/roster/type/women/ |
| Carolina Ascent FC | `CAR` | https://www.carolinaascent.com/roster/ |
| Dallas Trinity FC | `DAL` | https://www.dallastrinityfc.com/roster/ |
| D.C. Power FC | `DC` | https://www.dcpowerfootballclub.com/roster/ |
| Lexington SC | `LEX` | https://www.lexsporting.com/roster/type/womens-roster/ |
| Sporting Club Jacksonville | `JAX` | https://www.sportingjax.com/roster/type/womens-roster/ |

For each team, extract every listed player's full name and their headshot
image's direct URL, then download each image to a staging directory, named:

```
<team_abbr-lowercase>-<slug>.<source-extension>
```

where `<slug>` is the name lowercased, spaces replaced with hyphens, and
accents/punctuation/parentheticals stripped to plain ASCII (e.g. "Sofía
García" -> `sofia-garcia`, matching `normalize_name()` in
`scripts/update_headshots.R` closely enough that the match step can find
them -- exact slugging doesn't matter, only the CSV's `scraped_name` column
does).

Keep the original source extension (`.jpg`/`.jpeg`/`.png`) -- the packing
script converts everything to compressed square JPEG regardless, so this is
just for the staging step.

Skip any placeholder/generic silhouette images -- not every player has a
real photo published yet.

While building the CSV (columns: `team_abbr,scraped_name,filename`), also
note each player's name exactly as displayed on the site -- that's what goes
in `scraped_name`.

### Per-site gotchas encountered last time

- **Brooklyn FC**: the roster page renders client-side (React); the static
  HTML has no roster data. Fetch the WordPress REST API directly instead:
  `https://www.brooklynfootballclub.com/wp-json/wp/v2/sec_roster?sec_roster_type=285&_embed`
  (`sec_roster_type=285` is the "women" taxonomy term).
- **Sporting Club Jacksonville**: the URL has had CDN edge-cache collisions
  with a different team's page before -- if the content looks wrong,
  re-fetch with a cache-busting query param.
- A couple of teams have had filename/player mismatches on their own CMS
  (e.g. an image literally named after a different player than the one it's
  attributed to on the roster page) -- these are data-quality issues on the
  team's own site, not scraping bugs. Spot-check a few downloaded images
  against the roster page if something looks off.

## 2. Matching, compressing, and packing

Once the CSV and staging directory of raw images are ready, run from the
project root:

```sh
Rscript scripts/update_headshots.R path/to/scraped_headshots.csv path/to/staging_dir/
```

This:

1. Pulls the full current-season USL Super League roster from ASA
   (`minimum_minutes = 0`, so bench players who haven't recorded a single
   action still show up as match candidates).
2. Matches each scraped name to an ASA `player_id`, **prioritizing
   last-name accuracy** over whole-name string similarity: an exact
   normalized last-name match within the same team is accepted even when
   the first name is a nickname or initials ASA doesn't record (e.g. "LJ
   Moore" scraped vs. ASA's "Juliet Moore" -- confirmed correct: the
   source image filename was literally `Juliet-LJ-Moore.png`). A
   first-name-only coincidence across *different* last names is
   deliberately rejected (e.g. "Audrey Coleman" vs. ASA's "Audrey
   Harding" -- different people). This matters because the stats-endpoint
   roster (used for this team-scoped pass) is incomplete -- only players
   with at least one recorded action -- so a blanket fuzzy-match threshold
   would regularly produce confident-looking wrong matches for players ASA
   hasn't recorded stats for yet.
3. For anyone still unmatched (no stats-endpoint record at all), falls
   back to an **exact**-name-only match against `get_players()` -- ASA's
   full player list for the league (hundreds of rows, vs. ~150 in the
   stats endpoints), which includes zero-action players but has no
   `team_id` to cross-check against. Exact match only here, never fuzzy,
   since there's no team signal to disambiguate a near-miss.
4. A short list of `manual_overrides`/`cross_team` cases at the top of the
   script covers judgment calls no algorithm can infer (e.g. a player who
   goes by two different first names across sources, confirmed by a
   human). Add to these as new ones turn up -- don't loosen the matching
   thresholds instead, since that's what causes wrong-player mismatches.
5. Square-crops every image (biased 15% toward the top for portrait
   sources, to avoid cutting off foreheads), resizes to 300x300, and
   compresses to JPEG quality 85 -- these render at ~130px in the final
   table, so there's no reason to keep multi-megapixel originals (this
   step alone took the asset size from ~100MB to ~3MB last time).
6. Packs **every** scraped photo -- matched or not -- into
   `assets/headshots.parquet`, overwriting it. Unmatched photos are kept
   (`player_id` is `NULL`) rather than discarded, so a future re-run can
   wire them up once that player appears in ASA's data, without
   re-scraping. `R/headshots.R`'s `player_headshot_path()` only looks up
   rows with a non-null `player_id`, so unmatched rows simply render no
   headshot for that row -- same graceful-degradation pattern as
   `TEAM_LOGO_PATHS`.

The script refuses to write the parquet if two scraped photos resolved to
the same `player_id` (would mean one is wrong) -- fix the ambiguity in
`manual_overrides` or the source data before re-running.

Review the printed match summary before trusting the result, especially any
`fuzzy_both` or `last_name_exact_first_tiebreak` matches -- re-run with
`DBI::dbGetQuery()` against the new parquet, or just regenerate a test image
(see the project's test workflow) and eyeball a few rows.

## Known gaps (as of 2026-10-04)

173/183 scraped photos are matched. The remaining 10 scraped players likely
haven't recorded enough ASA-tracked actions to show up in `get_players()`
yet -- probably very recent signings or academy call-ups:

| Team | Scraped name |
|---|---|
| DAL | Heather MacNab |
| DAL | Ro Reed |
| DC | Ellie Gilbert |
| FTL | Jules Cagle |
| JAX | Amanda Poorbaugh |
| LEX | Bridget Kopmeyer |
| TB | Addison Jericho |
| TB | Jaeda Russell |
| TB | Kallie Bleistein |
| TB | Millie Ravening |

Plus one 2026-season ASA player with no scraped photo at all (not found on
the team's roster page when last scraped, or listed under a different
name): **Meila Brewer** (DAL).

Worth re-checking next time `scripts/update_headshots.R` is re-run -- ASA's
data may have caught up with these players by then.
