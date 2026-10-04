#' Authenticate against Bluesky using atrrr, from env vars.
#'
#' Reads BSKY_HANDLE / BSKY_APP_PASSWORD (an app password, not the main
#' account password) and establishes the session atrrr reuses for both
#' reading ASA's feed and posting our own skeets.
bsky_auth <- function() {
  handle <- Sys.getenv("BSKY_HANDLE")
  password <- Sys.getenv("BSKY_APP_PASSWORD")

  if (identical(handle, "") || identical(password, "")) {
    stop("BSKY_HANDLE and BSKY_APP_PASSWORD must be set (see .env.example)")
  }

  atrrr::auth(user = handle, password = password)
}
