# usl-gplus-bot

Watches American Soccer Analysis's Bluesky account (`@americansocceranalysis.com`)
for their NWSL "Goals Added (g+) and xG Leaders" post as a timing signal, then
independently builds and posts the USL Super League equivalent, sourced live
from ASA's own `itscalledsoccer` data.

It does not repost, quote, or copy ASA's content — only their post's
existence/timing is used as a trigger. The USL Super League graphics are
rendered locally from fresh API data.

## How it works

1. `main.R` polls ASA's Bluesky feed every `POLL_INTERVAL_SECONDS` (default 1200s / 20min).
2. When a post matching `is_nwsl_leaders_post()` (in `R/trigger.R`) appears and hasn't
   already been handled (tracked in a DuckDB table), it triggers `post_leaders()`.
3. `post_leaders()` (`R/post.R`) pulls USL Super League g+ and xG leaders via
   `itscalledsoccer` (`R/data.R`), renders two PNG tables styled after ASA's own
   (`R/render.R`), and publishes them as a new post via `atrrr`.

## Setup

```sh
cp .env.example .env
# fill in BSKY_HANDLE / BSKY_APP_PASSWORD (create an app password at
# https://bsky.app/settings/app-passwords -- do not use your main password)
```

Install dependencies (uses [pak](https://pak.r-lib.org/), pulling binaries
from CRAN where available for your R version/OS):

```r
install.packages("pak")
pak::local_install_deps(dependencies = TRUE)
```

Run locally:

```sh
Rscript main.R
```

Run tests:

```sh
Rscript -e 'testthat::test_dir("tests/testthat")'
```

## Data notes

A few non-obvious `itscalledsoccer`/ASA API quirks `R/data.R` works around:

- The league argument is the short code `"usls"`, not `"USL Super League"`.
- `get_player_goals_added()`/`get_player_xgoals()` return season *totals*,
  not per-96 rates, despite ASA's own graphics being per-96 -- `R/data.R`
  computes `stat / minutes_played * 96` itself.
- Without a `season_name` filter, those endpoints return stats aggregated
  across *every* season on record, not just the current one -- `R/data.R`
  always passes `season_name = current_season()` (the current year).
- `team_id` comes back as a list column (players who changed teams have more
  than one entry); `R/data.R` takes the most recent team for display.

## Team logos

`itscalledsoccer` doesn't expose crest URLs. Add each team's logo manually to
`assets/logos/` and register it in `R/teams.R`'s `TEAM_LOGO_PATHS`. Until a
team is registered, its row simply renders without a logo (the table doesn't
fail) -- and until *any* team is registered, the logo column is omitted
entirely.

## Player headshots

Headshots are scraped from each team's own roster page (site structure
differs per team -- no shared CMS across the league), matched to ASA's
`player_id` by name (prioritizing last-name accuracy over whole-name
similarity, since ASA's roster is incomplete and a blanket fuzzy-match
threshold would confidently attach the wrong photo to the wrong player),
and packed into a single `assets/headshots.parquet` -- one row per scraped
player (`team_abbr`, `scraped_name`, `player_id`, `content_type`, JPEG
bytes), resized to 300x300 and compressed (~3MB total vs. the ~100MB the
raw scraped originals would otherwise add to the repo). Unmatched players
(no 2026 actions recorded yet) are kept in the parquet rather than
discarded, so a later re-run can wire them up without re-scraping.
`R/headshots.R`'s `player_headshot_path()` queries it via `duckdb` at
render time and materializes the matched row to a tempfile for `gt` to
embed. A missing entry renders no headshot for that row rather than
failing the whole table, same as `TEAM_LOGO_PATHS`.

See [`docs/headshots.md`](docs/headshots.md) for the full process to redo
this (e.g. to pick up new signings or updated photos).

Re-scraping to pick up new signings/updated photos is a manual process for
now -- there's no automated refresh job.

## Deployment

A GitHub Actions workflow (`.github/workflows/docker-build.yml`) builds and
pushes the image to GHCR (`ghcr.io/ryanscharf/usl-gplus-bot:latest`) on
every push to `main`. On the TrueNAS box, run it via [`docker-compose.yml`](docker-compose.yml)
in [Dockge](https://github.com/louislam/dockge): add it as a stack, paste
the compose file in, then set `BSKY_HANDLE`/`BSKY_APP_PASSWORD` (and
optionally `POLL_INTERVAL_SECONDS`/`DB_PATH`) in Dockge's environment
variables tab -- the compose file reads them via `${VAR}` substitution, so
whatever Dockge writes to the stack's `.env` just works.

Outside Dockge, it's an ordinary compose file:

```sh
cp .env.example .env
# fill in BSKY_HANDLE / BSKY_APP_PASSWORD
docker compose up -d
```

`./data` on the host persists the DuckDB dedupe state across container
restarts/image updates (mounted to `/app/data`, matching `DB_PATH`'s
default in `.env.example`). To pick up a new image after a push to `main`,
`docker compose pull && docker compose up -d`.
