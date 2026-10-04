#' Compose and publish the USL Super League leaders post to Bluesky.

post_leaders <- function(handle = Sys.getenv("BSKY_HANDLE")) {
  as_of_date <- Sys.Date()

  client <- asa_client()
  gplus_df <- leaders_gplus(client)
  xg_df <- leaders_xg(client)

  gplus_png <- render_png(
    build_leaders_table(gplus_df, "gplus", as_of_date, handle),
    file.path(tempdir(), "usls_gplus.png")
  )
  xg_png <- render_png(
    build_leaders_table(xg_df, "xg", as_of_date, handle),
    file.path(tempdir(), "usls_xg.png")
  )

  text <- glue::glue(
    "USL Super League Goals Added (g+) and xG Leaders ⬇️\n(as of: {as_of_date})\n\n\U0001F916⚽️ | #usls"
  )

  atrrr::post_skeet(
    text = text,
    image = c(gplus_png, xg_png),
    image_alt = c(
      "USL Super League goals added table",
      "USL Super League xG table"
    ),
    langs = "en"
  )
}
