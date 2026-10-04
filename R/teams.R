#' Static team crest lookup.
#'
#' itscalledsoccer doesn't expose logo URLs. Team crests are a small,
#' stable set (unlike player headshots) -- source each one once manually
#' (team site / Wikipedia) and commit it under assets/logos/, named by the
#' team's itscalledsoccer abbreviation.
#'
#' Populate this as teams are added; a missing entry renders no crest for
#' that row rather than failing the whole table.
TEAM_LOGO_PATHS <- c(
  "BKN" = "assets/logos/bkn.png",
  "CAR" = "assets/logos/car.png",
  "DC" = "assets/logos/dc.png",
  "DAL" = "assets/logos/dal.png",
  "FTL" = "assets/logos/ftl.png",
  "LEX" = "assets/logos/lex.png",
  "SPK" = "assets/logos/spk.png",
  "JAX" = "assets/logos/jax.png",
  "TB" = "assets/logos/tb.png"
)

team_logo_path <- function(team_abbreviation) {
  path <- TEAM_LOGO_PATHS[team_abbreviation]
  if (is.na(path) || !file.exists(path)) {
    return(NA_character_)
  }
  normalizePath(path)
}
