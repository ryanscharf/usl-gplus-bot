#' Entry point: long-running poll loop.
#'
#' Watches ASA's Bluesky account for their NWSL g+/xG leaders post as a
#' timing signal, then independently builds and posts the USL Super League
#' equivalent using itscalledsoccer data.

dotenv::load_dot_env(".env")

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}

POLL_INTERVAL_SECONDS <- as.integer(Sys.getenv("POLL_INTERVAL_SECONDS", "1200"))

main <- function() {
  bsky_auth()
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  message("usl-gplus-bot started, polling every ", POLL_INTERVAL_SECONDS, "s")

  repeat {
    tryCatch(
      {
        check_for_trigger(con, on_trigger = function(post) {
          message("[trigger] matched ASA post ", post$uri, " -- posting USL Super League leaders")
          post_leaders()
        })
      },
      error = function(e) {
        message("[main] poll cycle failed: ", conditionMessage(e))
      }
    )

    Sys.sleep(POLL_INTERVAL_SECONDS)
  }
}

main()
