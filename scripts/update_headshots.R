#' Match scraped player headshots to ASA player_ids and pack them into
#' assets/headshots.parquet.
#'
#' This is the automatable second half of the headshot pipeline -- see
#' docs/headshots.md for the full process, including the scraping step
#' (which isn't automated here: each team's roster page has a different
#' site structure, so there's no stable scraper to maintain).
#'
#' Usage (from the project root):
#'   Rscript scripts/update_headshots.R <scraped_csv> <staging_dir>
#'
#' <scraped_csv> has columns: team_abbr,scraped_name,filename
#'   (filename = the name the image was saved under in <staging_dir>, with
#'   its original/source extension -- this script converts everything to
#'   square-cropped JPEG regardless)
#' <staging_dir> contains the raw downloaded images named per filename above.
#'
#' Run from the project root; sources R/data.R for asa_client()/LEAGUE/
#' current_season(), and requires the magick, DBI and duckdb packages.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) {
  stop("Usage: Rscript scripts/update_headshots.R <scraped_csv> <staging_dir>")
}
scraped_csv <- args[1]
staging_dir <- args[2]

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
library(magick)

scraped <- read.csv(scraped_csv, stringsAsFactors = FALSE)

# --- 1. Pull the full current-season roster (minimum_minutes = 0, so bench
# players who haven't recorded a single action still show up) to match
# against. ---
client <- asa_client()
gplus_all <- client$get_player_goals_added(leagues = LEAGUE, season_name = current_season(), above_replacement = TRUE, minimum_minutes = 0)
xg_all <- client$get_player_xgoals(leagues = LEAGUE, season_name = current_season(), minimum_minutes = 0)

ids <- unique(rbind(
  data.frame(player_id = gplus_all$player_id, team_id = I(gplus_all$team_id)),
  data.frame(player_id = xg_all$player_id, team_id = I(xg_all$team_id))
))
ids <- ids[!duplicated(ids$player_id), ]
ids$team_id <- vapply(ids$team_id, utils::tail, character(1), n = 1)

players <- client$get_players(leagues = LEAGUE)
teams <- client$get_teams(leagues = LEAGUE)
roster <- merge(ids, players[, c("player_id", "player_name")], by = "player_id")
roster <- merge(roster, teams[, c("team_id", "team_abbreviation")], by = "team_id")

# get_players() is the FULL player list ASA has on record for this league
# (429 rows, vs. 154 in the stats endpoints above) -- it includes players
# who haven't recorded a single tracked action yet, just without a team_id
# (that only comes from the stats endpoints). Used as a second-pass,
# exact-name-only fallback below for players the team-scoped match above
# can't place.
all_players <- players

# --- 2. Name matching, prioritizing last-name accuracy. ---
#
# ASA's roster is incomplete (only players who've recorded at least one
# action), so some scraped players legitimately have no match yet -- a
# forced nearest-neighbor match would silently attach the wrong photo to
# the wrong player, which is worse than no photo. An exact last-name match
# within the same team is strong enough evidence to accept even when the
# first name is a nickname/initials ASA doesn't record (e.g. "LJ Moore" is
# ASA's "Juliet Moore"); a first-name-only coincidence across different
# last names is NOT accepted (e.g. "Audrey Coleman" vs "Audrey Harding").
normalize_name <- function(x) {
  x <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT")
  x <- gsub("\\([^)]*\\)", "", x) # drop parenthetical nicknames
  x <- gsub("'[^']*'", "", x) # drop 'quoted' nicknames
  x <- gsub("'", "", x) # stray apostrophe (e.g. "Sh'nia") -- drop, don't space-split
  x <- gsub("[^A-Za-z ]", " ", x)
  tolower(trimws(gsub("\\s+", " ", x)))
}
last_name <- function(x) {
  tokens <- strsplit(x, " ")[[1]]
  if (length(tokens) == 0) return("")
  tokens[length(tokens)]
}
first_name <- function(x) {
  tokens <- strsplit(x, " ")[[1]]
  if (length(tokens) == 0) return("")
  tokens[1]
}

scraped$norm <- normalize_name(scraped$scraped_name)
roster$norm <- normalize_name(roster$player_name)
scraped$last <- vapply(scraped$norm, last_name, character(1))
roster$last <- vapply(roster$norm, last_name, character(1))
scraped$first <- vapply(scraped$norm, first_name, character(1))
roster$first <- vapply(roster$norm, first_name, character(1))
all_players$norm <- normalize_name(all_players$player_name)

# Judgment calls no algorithm can infer -- add to these as new ones turn up.
# Keys are "<team_abbr>|<normalized scraped name>", values are the
# normalized ASA player_name to match to.
manual_overrides <- list(
  "DAL|jasmine hamid" = "ishata hamid", # user-confirmed: same player, goes by both names
  "BKN|annie williams arlington" = "antoinette williams", # shared surname, hyphenated/nickname variant
  "DC|loza abera" = "loza geinore" # rare first name match, likely maiden/married name difference
)
# Players who moved teams mid-season: ASA's most-recent-team resolution can
# lag the team site's current roster -- match by name across all teams.
cross_team <- list("nicole vernis" = "nicole vernis")

match_one <- function(row) {
  key <- paste0(row$team_abbr, "|", row$norm)
  candidates <- roster[roster$team_abbreviation == row$team_abbr, ]

  exact <- candidates[candidates$norm == row$norm, ]
  if (nrow(exact) == 1) {
    return(data.frame(player_id = exact$player_id, asa_player_name = exact$player_name, method = "exact"))
  }

  if (!is.null(manual_overrides[[key]])) {
    m <- candidates[candidates$norm == manual_overrides[[key]], ]
    if (nrow(m) == 1) {
      return(data.frame(player_id = m$player_id, asa_player_name = m$player_name, method = "manual"))
    }
  }

  if (!is.null(cross_team[[row$norm]])) {
    m <- roster[roster$norm == cross_team[[row$norm]], ]
    if (nrow(m) == 1) {
      return(data.frame(player_id = m$player_id, asa_player_name = m$player_name, method = "cross_team"))
    }
  }

  if (nrow(candidates) == 0 || row$last == "") {
    return(data.frame(player_id = NA_character_, asa_player_name = NA_character_, method = "unmatched"))
  }

  last_dists <- utils::adist(row$last, candidates$last)[1, ]
  exact_last <- candidates[last_dists == 0, ]

  if (nrow(exact_last) == 1) {
    return(data.frame(player_id = exact_last$player_id, asa_player_name = exact_last$player_name, method = "last_name_exact"))
  }
  if (nrow(exact_last) > 1) {
    first_dists <- utils::adist(row$first, exact_last$first)[1, ]
    best <- which.min(first_dists)
    if (first_dists[best] <= 2) {
      return(data.frame(player_id = exact_last$player_id[best], asa_player_name = exact_last$player_name[best], method = "last_name_exact_first_tiebreak"))
    }
    return(data.frame(player_id = NA_character_, asa_player_name = NA_character_, method = "ambiguous_surname"))
  }

  near <- which(last_dists <= 2)
  if (length(near) > 0) {
    first_dists <- utils::adist(row$first, candidates$first[near])[1, ]
    best <- near[which.min(first_dists)]
    if (last_dists[best] <= 2 && min(first_dists) <= 2) {
      return(data.frame(player_id = candidates$player_id[best], asa_player_name = candidates$player_name[best], method = "fuzzy_both"))
    }
  }

  # Last resort: no team-scoped candidate at all (player has zero recorded
  # 2026 actions, so they're absent from the stats-endpoint roster entirely)
  # -- fall back to an EXACT name match against ASA's full player list
  # (get_players(), which has no team_id but is far more complete). Exact
  # name only, no fuzzy matching, since we can't cross-check team here.
  full_exact <- all_players[all_players$norm == row$norm, ]
  if (nrow(full_exact) == 1) {
    return(data.frame(player_id = full_exact$player_id, asa_player_name = full_exact$player_name, method = "full_roster_exact"))
  }

  data.frame(player_id = NA_character_, asa_player_name = NA_character_, method = "unmatched")
}

matches <- do.call(rbind, lapply(seq_len(nrow(scraped)), function(i) {
  cbind(scraped[i, ], match_one(scraped[i, ]))
}))

cat("Method counts:\n")
print(table(matches$method, useNA = "always"))
cat("\nMatched:", sum(!is.na(matches$player_id)), "/", nrow(matches), "\n")

dupes <- matches[!is.na(matches$player_id), ]
dupes <- dupes[duplicated(dupes$player_id) | duplicated(dupes$player_id, fromLast = TRUE), ]
if (nrow(dupes) > 0) {
  stop(
    "Refusing to pack: duplicate player_id matches found (two scraped photos ",
    "resolved to the same player) -- review manually:\n",
    paste(capture.output(print(dupes[, c("team_abbr", "scraped_name", "player_id", "asa_player_name")])), collapse = "\n")
  )
}

# --- 3. Square-crop + resize + compress every scraped image. ---
#
# gt::local_image()/gtExtras only control image *height*, not width, so
# source photos with different aspect ratios render as a ragged column next
# to the uniform circular crests -- crop everyone to a consistent square
# first. Bias the vertical crop 15% toward the top for portrait sources, to
# avoid cutting off foreheads on tightly-cropped photos.
crop_square <- function(img) {
  info <- image_info(img)
  w <- info$width
  h <- info$height
  sq <- min(w, h)
  if (h > w) {
    x_off <- 0
    y_off <- round((h - sq) * 0.15)
  } else {
    x_off <- round((w - sq) / 2)
    y_off <- 0
  }
  image_crop(img, geometry_area(sq, sq, x_off, y_off))
}

cat("\nCompressing", nrow(scraped), "images...\n")
images <- lapply(seq_len(nrow(scraped)), function(i) {
  path <- file.path(staging_dir, scraped$filename[i])
  img <- image_read(path)
  img <- crop_square(img)
  img <- image_flatten(image_background(img, "white")) # drop alpha for JPEG
  img <- image_resize(img, "300x300")
  img <- image_convert(img, format = "jpeg")
  image_write(img, format = "jpeg", quality = 85)
})

# --- 4. Pack everything -- matched or not -- into the parquet. ---
#
# Unmatched photos are kept (player_id NA) rather than discarded, so a
# future re-run can wire them up once that player appears in ASA's data,
# without re-scraping.
df <- data.frame(
  team_abbr = matches$team_abbr,
  scraped_name = matches$scraped_name,
  player_id = matches$player_id,
  content_type = "image/jpeg",
  stringsAsFactors = FALSE
)
df$image <- images

out_path <- "assets/headshots.parquet"
con <- DBI::dbConnect(duckdb::duckdb())
duckdb::duckdb_register(con, "headshots_tbl", df)
DBI::dbExecute(con, sprintf("COPY headshots_tbl TO '%s' (FORMAT PARQUET)", out_path))
DBI::dbDisconnect(con, shutdown = TRUE)

cat(sprintf(
  "\nWrote %d rows (%d matched) to %s (%.2f MB)\n",
  nrow(df), sum(!is.na(df$player_id)), out_path, file.info(out_path)$size / 1024^2
))
