#' itscalledsoccer client wrapper for USL Super League leaders.

LEAGUE <- "usls"
MINIMUM_MINUTES <- 300

#' Current season year, as the API's season_name expects it.
#'
#' Without season_name, get_player_goals_added()/get_player_xgoals() return
#' stats aggregated across every season on record, not just the current one.
current_season <- function() {
  format(Sys.Date(), "%Y")
}

asa_client <- function() {
  itscalledsoccer::AmericanSoccerAnalysis$new()
}

#' Top-10 USL Super League players by goals added above average (g+) per 96.
#'
#' get_player_goals_added() returns season totals, not per-96 rates -- the
#' API has no built-in normalization, so it's computed here.
leaders_gplus <- function(client = asa_client(), n = 10) {
  gplus <- client$get_player_goals_added(
    leagues = LEAGUE,
    season_name = current_season(),
    above_replacement = TRUE,
    minimum_minutes = MINIMUM_MINUTES
  )

  gplus$goals_added_above_replacement_p96 <-
    gplus$goals_added_above_replacement / gplus$minutes_played * 96

  gplus <- gplus[order(-gplus$goals_added_above_replacement_p96), ]
  gplus <- utils::head(gplus, n)

  join_player_team_info(client, gplus)
}

#' Top-10 USL Super League players by expected goals (xG) per 96.
#'
#' get_player_xgoals() returns season totals, not per-96 rates -- the API
#' has no built-in normalization, so it's computed here.
leaders_xg <- function(client = asa_client(), n = 10) {
  xg <- client$get_player_xgoals(
    leagues = LEAGUE,
    season_name = current_season(),
    minimum_minutes = MINIMUM_MINUTES
  )

  xg$xgoals_p96 <- xg$xgoals / xg$minutes_played * 96

  xg <- xg[order(-xg$xgoals_p96), ]
  xg <- utils::head(xg, n)

  join_player_team_info(client, xg)
}

#' Attach player name and team name/abbreviation to a leaders df.
#'
#' get_player_goals_added()/get_player_xgoals() return player_id/team_id
#' (plus general_position already) -- resolve those against
#' get_players()/get_teams() for display purposes.
join_player_team_info <- function(client, df) {
  players <- client$get_players(leagues = LEAGUE)
  teams <- client$get_teams(leagues = LEAGUE)

  # team_id comes back as a list column (players who changed teams mid-season
  # have more than one) -- take the most recent team for display.
  df$team_id <- vapply(df$team_id, utils::tail, character(1), n = 1)

  df <- merge(df, players[, c("player_id", "player_name")],
    by = "player_id", all.x = TRUE
  )
  df <- merge(df, teams[, c("team_id", "team_name", "team_abbreviation")],
    by = "team_id", all.x = TRUE
  )

  sort_col <- if ("goals_added_above_replacement_p96" %in% names(df)) "goals_added_above_replacement_p96" else "xgoals_p96"
  df[order(-df[[sort_col]]), ]
}
