test_that("matches ASA's real NWSL leaders post text", {
  real_text <- "NWSL Goals Added (g+) and xG Leaders  ⬇️\n(as of: 2026-09-21)\n\n\U0001F916⚽️ | #nwsl"
  expect_true(is_nwsl_leaders_post(real_text))
})

test_that("does not match unrelated posts", {
  expect_false(is_nwsl_leaders_post("Just a regular update about the league."))
  expect_false(is_nwsl_leaders_post("MLS Goals Added (g+) and xG Leaders (as of: 2026-05-18)"))
})

test_that("handles NA/NULL safely", {
  expect_false(is_nwsl_leaders_post(NA_character_))
  expect_false(is_nwsl_leaders_post(NULL))
})
