#' Detect and dedupe ASA's NWSL "Goals Added (g+) and xG Leaders" post.
#'
#' USL Super League is also a women's league, so its matchweek cadence
#' tracks NWSL's more closely than MLS's -- we use ASA's NWSL leaders post
#' as the timing signal for publishing our own USL Super League version.

#' @param text A Bluesky post's text.
#' @return TRUE if this looks like ASA's NWSL g+/xG leaders post.
is_nwsl_leaders_post <- function(text) {
  if (is.null(text) || is.na(text)) {
    return(FALSE)
  }

  grepl("NWSL", text, ignore.case = TRUE) &&
    grepl("Goals Added|g\\+", text, ignore.case = TRUE) &&
    grepl("Leaders", text, ignore.case = TRUE)
}

#' Poll ASA's feed for an unhandled NWSL leaders post.
#'
#' @param con DuckDB connection from db_connect().
#' @param on_trigger Function called with the matched post row when a new,
#'   unhandled trigger is found.
check_for_trigger <- function(con, on_trigger, actor = "americansocceranalysis.com") {
  feed <- atrrr::get_skeets_authored_by(
    actor = actor,
    limit = 25,
    filter = "posts_no_replies"
  )

  if (is.null(feed) || nrow(feed) == 0) {
    return(invisible(NULL))
  }

  matches <- feed[vapply(feed$text, is_nwsl_leaders_post, logical(1)), ]

  for (i in seq_len(nrow(matches))) {
    post <- matches[i, ]

    if (has_handled(con, post$uri)) {
      next
    }

    tryCatch(
      {
        on_trigger(post)
        mark_handled(con, post$uri, as.character(post$created_at))
      },
      error = function(e) {
        message(glue::glue(
          "[trigger] failed to handle {post$uri}: {conditionMessage(e)} (will retry next cycle)"
        ))
      }
    )
  }

  invisible(NULL)
}
