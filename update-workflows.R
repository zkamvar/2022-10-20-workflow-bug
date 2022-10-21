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
)

to_exclude <- readLines("pull-log.md") |> trimws() |> c(workbench_repos)
to_exclude <- sub("^https://github.com/[^/]+/([^/]+)/pull/.+$", "\\1", to_exclude)

# all official repos that were built with styles and are still active
official_repos <- jsonlite::read_json("data/lessons.json") |>
  purrr::discard(\(x) x$life_cycle == "on-hold" | x$repo %in% to_exclude)
names(official_repos) <- purrr::map_chr(official_repos, "repo")


# all community repos that were built with styles or the template
community_repos <- jsonlite::read_json("data/community_lessons.json") |>
  purrr::discard(\(x) x$life_cycle == "on-hold" | x$repo %in% to_exclude)
names(community_repos) <- purrr::map_chr(community_repos, "repo")

tmpdir <- setup_tmpdir()

official_dirs <- purrr::map(official_repos, get_repository, tmpdir)
official_res <- purrr::map(official_dirs, patch_and_report)
names(official_res) <- names(official_repos)
record_prs(official_res)
official_problems <- record_problems(official_res, official_repos)

community_dirs <- purrr::map(community_repos, get_repository, tmpdir)
community_res <- purrr::map(community_dirs, patch_and_report)
names(community_res) <- names(community_repos)
record_prs(community_res)
community_problems <- record_problems(community_res, community_repos)
