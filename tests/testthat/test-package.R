test_that("the package installs and the test suite runs on edition 3", {
  expect_equal(edition_get(), 3L)
})
