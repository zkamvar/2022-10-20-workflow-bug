library("fs")
library("gert")
library("yaml")
library("jsonlite")
library("withr")
library("purrr")


source("functions.R")

# we do not want any of the workbench repositories to be included here.
workbench_repos <- c("workbench-template-md", 
  "workbench-template-rmd",
  "sandpaper-docs", 
  "lesson-development-training", 
  "R-ecology-lesson", 
  "CarpentriesOffline_Instructor_Onboarding",
  "intro-data-viz",
  "r-tidyverse-4-datasets",
  "iot-novice",
  "python-modeling-power-consumption",
  "python-classifying-power-consumption",
  "R-ecology-lesson-intermediate",
  "encode-data-exploration",
  "instructor-training", # already submitted as a test
  "cwl-novice-tutorial"
)

# all official repos that were built with styles and are still active
official_repos <- jsonlite::read_json("data/lessons.json") |>
  purrr::discard(\(x) x$life_cycle == "on-hold" | x$repo %in% workbench_repos) |>
  purrr::map(\(x) x[names(x) != "github_topics"]) 

# all community repos that were built with styles or the template
community_repos <- jsonlite::read_json("data/community_lessons.json") |>
  purrr::discard(\(x) x$life_cycle == "on-hold" | x$repo %in% workbench_repos) |>
  purrr::map(\(x) x[names(x) != "github_topics"])

tmpdir <- setup_tmpdir()

official_dirs <- purrr::map(official_repos, get_repository, tmpdir)
purrr::map(official_dirs, \(x) {
  Sys.sleep(2)
  name <- fs::path_split(x)[[1]]
  name <- fs::path(paste(name[length(name) - 1:0], collapse = "/"))
  res <- tryCatch(create_patch(x), error = function(e) e)
  if (!inherits(x, "error")) {
    message(sprintf("     PR for %s successfully submitted!", name))
    fs::dir_delete(x)
    TRUE
  } else {
    message(sprintf("ERROR in %s: %s", name, res$stderr))
  }
})

community_dirs <- purrr::map(community_repos, get_repository, tmpdir)
purrr::walk(community_dirs, \(x) {
  res <- tryCatch(create_patch(repodir), error = function(e) e)
  if (!inherits(x, "error")) {
    fs::dir_delete(repodir)
  }
})



