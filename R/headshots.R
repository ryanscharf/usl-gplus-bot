#' Player headshot lookup, keyed by itscalledsoccer player_id.
#'
#' Headshots are packed into a single assets/headshots.parquet (one row per
#' scraped player: team_abbr, scraped_name, player_id, content_type, image
#' bytes) rather than kept as ~180 loose files, to stay git-friendly. Built
#' by scraping each team's own roster page (site structure differs per team)
#' and matching scraped names against the ASA player_id via R/data.R's
#' player roster, prioritizing last-name accuracy (an exact last-name match
#' within a team is accepted even when the first name is a nickname/initials
#' ASA doesn't record, e.g. "LJ Moore" -> "Juliet Moore"; first-name-only
#' coincidences across different last names are rejected). 38 of 183 scraped
#' players have no 2026 USL Super League actions recorded yet, so they don't
#' appear in get_player_goals_added()/get_player_xgoals() and can't be
#' matched -- their photos are still kept in the parquet (player_id NA)
#' rather than discarded, so a future re-run of the matching script can wire
#' them up once they do appear in ASA's data, without re-scraping.
#'
#' A missing entry renders no headshot for that row rather than failing the
#' whole table -- same graceful-degradation pattern as TEAM_LOGO_PATHS.
HEADSHOTS_PARQUET <- "assets/headshots.parquet"

#' Look up a player's headshot and write it to a temp file for gt to embed.
#'
#' gt::local_image() needs a file path, not raw bytes, so this materializes
#' the matched row to a tempfile() on each call rather than keeping the
#' parquet's images decoded in memory for the whole session.
player_headshot_path <- function(player_id) {
  if (!file.exists(HEADSHOTS_PARQUET)) {
    return(NA_character_)
  }

  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  row <- DBI::dbGetQuery(
    con,
    "SELECT content_type, image FROM read_parquet(?) WHERE player_id = ?",
    params = list(HEADSHOTS_PARQUET, player_id)
  )

  if (nrow(row) == 0) {
    return(NA_character_)
  }

  ext <- if (identical(row$content_type[[1]], "image/jpeg")) "jpg" else "png"
  path <- tempfile(fileext = paste0(".", ext))
  writeBin(row$image[[1]], path)
  path
}
