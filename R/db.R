#' DuckDB-backed dedupe store for ASA trigger posts we've already handled.

db_connect <- function(path = Sys.getenv("DB_PATH", "data/state.duckdb")) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = path)

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS handled_triggers (
      source_uri TEXT PRIMARY KEY,
      source_created_at TEXT,
      handled_at TEXT NOT NULL
    )
  ")

  con
}

has_handled <- function(con, source_uri) {
  res <- DBI::dbGetQuery(
    con,
    "SELECT 1 FROM handled_triggers WHERE source_uri = ?",
    params = list(source_uri)
  )
  nrow(res) > 0
}

mark_handled <- function(con, source_uri, source_created_at) {
  # A zero-length value here makes DuckDB's bind fail, which previously left
  # posts unrecorded and caused reposts every cycle.
  if (length(source_created_at) != 1) {
    source_created_at <- NA_character_
  }

  DBI::dbExecute(
    con,
    "INSERT INTO handled_triggers (source_uri, source_created_at, handled_at) VALUES (?, ?, ?)",
    params = list(source_uri, source_created_at, format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  )
}
