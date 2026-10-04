#' Render a USL Super League leaders table as a PNG, matching ASA's style:
#' title / "Until <date> | @handle" subtitle / Rank-Logo-Name-Position-stat
#' columns with dashed row separators / footer stat note + data + viz credit.

#' @param handle Handle to credit (the same one used in the subtitle).
viz_credit <- function(handle) {
  glue::glue("Viz: @{handle} ripping off @catabush")
}

#' Render a local-file image column, blank for NA paths.
#'
#' gtExtras::gt_img_rows() renders a broken-image icon instead of a blank
#' cell for NA paths (confirmed via isolated repro -- its NA-branch
#' text_transform does fire with the right rows, but the image still shows
#' broken, so the bug is inside gt_img_rows itself). This reimplements the
#' same two-text_transform approach directly against gt/local_image(),
#' which handles NA correctly.
gt_img_rows_local <- function(gt_obj, column, height) {
  vals <- gt_obj[["_data"]][[column]]
  gt_obj |>
    gt::text_transform(
      locations = gt::cells_body(column, rows = which(!is.na(vals))),
      fn = function(x) gt::local_image(filename = x, height = height)
    ) |>
    gt::text_transform(
      locations = gt::cells_body(column, rows = which(is.na(vals))),
      fn = function(x) ""
    )
}

#' @param df Output of leaders_gplus() or leaders_xg(), already top-n and sorted.
#' @param metric "gplus" or "xg".
#' @param as_of_date Date (or string) for the "Until <date>" subtitle.
#' @param handle Our Bluesky handle for the subtitle.
build_leaders_table <- function(df, metric = c("gplus", "xg"), as_of_date, handle) {
  metric <- match.arg(metric)

  title <- switch(metric,
    gplus = "USL Super League Goals Added (g+) Leaders",
    xg = "USL Super League Expected Goals (xG) Leaders"
  )
  stat_col <- switch(metric, gplus = "goals_added_above_replacement_p96", xg = "xgoals_p96")
  stat_label <- switch(metric, gplus = "g+", xg = "xG")
  footnote <- switch(metric,
    gplus = "g+ is above average and per 96 mins | Min 1/3 mins played",
    xg = "xG per 96 mins | Min 1/3 mins played"
  )

  display <- data.frame(
    rank = seq_len(nrow(df)),
    logo = vapply(df$team_abbreviation, team_logo_path, character(1)),
    headshot = vapply(df$player_id, player_headshot_path, character(1)),
    name = df$player_name,
    position = df$general_position,
    stat = round(df[[stat_col]], 2),
    stringsAsFactors = FALSE
  )
  names(display)[names(display) == "stat"] <- stat_label

  # TEAM_LOGO_PATHS/PLAYER_HEADSHOT_PATHS can be incomplete (crests not yet
  # sourced, player not yet matched to a photo) -- skip an image column
  # entirely rather than handing gt_img_rows all-NA paths, which it can't
  # render.
  has_logos <- any(!is.na(display$logo))
  if (!has_logos) {
    display$logo <- NULL
  }
  has_headshots <- any(!is.na(display$headshot))
  if (!has_headshots) {
    display$headshot <- NULL
  }

  tbl <- gt::gt(display) |>
    gt::tab_header(
      title = title,
      subtitle = glue::glue("Until {as_of_date} | @{handle}")
    )

  if (has_logos) {
    tbl <- tbl |>
      gt_img_rows_local("logo", height = 100) |>
      gt::cols_label(logo = "")
  }
  if (has_headshots) {
    tbl <- tbl |>
      gt_img_rows_local("headshot", height = 130) |>
      gt::cols_label(headshot = "")
  }
  tbl <- tbl |>
    gt::cols_label(rank = "Rank", name = "Name", position = "Position")

  tbl <- tbl |>
    gt::cols_align(align = "left", columns = c("rank", "name")) |>
    gt::cols_align(align = "center", columns = "position") |>
    gt::cols_align(align = "right", columns = stat_label) |>
    gt::tab_source_note(footnote) |>
    gt::tab_source_note("Data: American Soccer Analysis") |>
    gt::tab_source_note(viz_credit(handle)) |>
    gt::tab_style(
      style = gt::cell_borders(sides = "top", color = "grey80", style = "dashed", weight = gt::px(2)),
      locations = gt::cells_body(rows = 2:nrow(display))
    ) |>
    gt::tab_style(
      style = gt::cell_borders(sides = "bottom", color = "black", weight = gt::px(3)),
      locations = gt::cells_column_labels(columns = gt::everything())
    ) |>
    gt::tab_style(
      style = gt::cell_text(color = "#1C9AD6"),
      locations = gt::cells_title(groups = "subtitle")
    ) |>
    gt::opt_table_font(font = gt::google_font("Rubik")) |>
    gt::tab_options(
      table.width = gt::px(2660),
      table.font.size = gt::px(44),
      table.border.top.style = "hidden",
      table.border.bottom.style = "hidden",
      heading.align = "left",
      heading.title.font.size = gt::px(76),
      heading.title.font.weight = "bold",
      heading.subtitle.font.size = gt::px(40),
      heading.padding = gt::px(30),
      column_labels.font.weight = "bold",
      column_labels.font.size = gt::px(38),
      column_labels.padding = gt::px(16),
      source_notes.font.size = gt::px(32),
      source_notes.padding = gt::px(14),
      table_body.border.bottom.color = "black",
      table_body.border.bottom.width = gt::px(3),
      data_row.padding = gt::px(22)
    )
}

#' @param gt_obj Output of build_leaders_table().
#' @param path Output PNG path.
render_png <- function(gt_obj, path, vwidth = 2800, vheight = 2600) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

  # gtsave()'s webshot2 backend defaults to selector = "table"/zoom = 2,
  # which crops to the table's natural content size and ignores
  # vwidth/vheight -- build our own HTML wrapper, left-aligned with a fixed
  # margin (matching ASA's own layout), on a fixed-size canvas, then capture
  # that exact viewport, to get a consistent 2800x2600 output regardless of
  # row count.
  html_doc <- glue::glue(
    "<html><head><meta charset='utf-8'></head>",
    "<body style='margin:0;width:{vwidth}px;height:{vheight}px;",
    "padding:70px;box-sizing:border-box;background:white;'>",
    "{gt::as_raw_html(gt_obj)}",
    "</body></html>"
  )
  tmp_html <- tempfile(fileext = ".html")
  writeLines(html_doc, tmp_html)

  webshot2::webshot(
    url = paste0("file:///", normalizePath(tmp_html, "/", mustWork = FALSE)),
    file = path,
    vwidth = vwidth, vheight = vheight,
    cliprect = "viewport", zoom = 1
  )
  path
}
