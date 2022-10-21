setup_tmpdir <- function() {
  tmp <- fs::file_temp()
  fs::dir_create(tmp)
  tmp
}

setup_repodir <- function(org, repo, tmpdir) {
  the_dir <- fs::path(tmpdir, org, repo)
  fs::dir_create(the_dir, recurse = TRUE)
}

get_repository <- function(lesson, tmpdir) {
  path <- setup_repodir(lesson$carpentries_org, lesson$repo, tmpdir)
  msg <- sprintf("Creating %s ------------", fs::path_rel(path, start = tmpdir))
  message(msg)
  if (!fs::dir_exists(fs::path(path, ".git"))) {
    gert::git_clone(lesson$repo_url, path = path)
  }
  path
}

checkout_branch <- function(path, branch = "znk-fix-workflows-2022-10-20") {
  current <- gert::git_branch(repo = path)
  if (gert::git_branch_exists(branch, repo = path)) {
    gert::git_branch_checkout(branch, repo = path)
  } else {
    gert::git_branch_create(branch, ref = "HEAD", checkout = TRUE, repo = path)
  }
  current
}

push <- function(path, branch = "znk-fix-workflows-2022-10-20") {
  upstream <- paste0("origin/", branch) 
  gert::git_branch_checkout(branch, repo = path)
  gert::git_push(set_upstream = TRUE, repo = path)
  body <- r"{This pull request updates the workflows for this lesson.

There are two items that are changed:

1. r-lib/actions/setup-r now uses `@v2` instead of `@master` as the default tag
2. the `set-output` GHA workflow command has been updated as it was deprecated.

see https://github.com/carpentries/styles/issues/641 for details

If you have any questions, contact @zkamvar}"
  tryCatch({
    processx::run("gh", 
      c("pr", "create",
        "--title", "urgent: fix workflows", 
        "--body", body),
        wd = path, echo = TRUE, echo_cmd = TRUE)
  }, error = function(e) e)
}

delete_branch <- function(path, head, branch = "znk-fix-workflows-2022-10-20") {
  gert::git_branch_checkout(head, repo = path)
  gert::git_branch_delete(branch, repo = path)
}

apply_patch <- function(path, patchfile = "workflow.patch") {
  patchfile <- fs::path_abs(patchfile)
  tryCatch({
    processx::run("git", c("am", "-3", patchfile), wd = path, 
    echo = TRUE, echo_cmd = TRUE)
  }, 
  error = function(e) {
    message("aborting")
    processx::run("git", c("am", "--abort"), wd = path, echo = TRUE, echo_cmd = TRUE)
    return(e)
  })
}

apply_workflows <- function(path, md5 = "workflow-md5.txt") {
  known <- read.table(md5)
  sha <- setNames(known[[1]], fs::path_file(known[[2]]))
  workflows <- fs::path(path, ".github/workflows/", names(sha))
  if (fs::dir_exists(fs::path_dir(workflows[1]))) {
    current <- tools::md5sum(workflows)
    names(current) <- fs::path_file(names(current))
    # returns status output of processx or error message
    if (all(current == sha)) {
      copy_and_commit(path, workflows)
    } else {
      # read in the workflows and modify accordingly
      parse_and_commit(path, workflows)
    }
  } else {
    msg <- "No workflow directory"
    message("No workflow directory. Update not needed")
    tryCatch(stop(msg), error = function(e) e)
  }
}

commit_workflows <- function(path, workflows) {
  to_add <- fs::path(".github/workflows", fs::path_file(workflows))
  gert::git_add(to_add, repo = path)
  # I am committing like this so that my signature is added
  tryCatch({
    processx::run("git", c("commit", "-m", 
      "use up-to-date r-lib action; update GHA syntax"), 
      wd = path, echo = TRUE, echo_cmd = TRUE)
    },
    error = function(e) e)
}

# OPTION 2: replace files ------------------------------------------------------
copy_and_commit <- function(path, workflows) {
  ours <- fs::path_file(workflows)
  fs::file_copy(ours, workflows)
  commit_workflows(path, workflows)
}

# OPTION 3: Replace lines in the file ------------------------------------------
parse_and_commit <- function(path, workflows) {
  purrr::walk(workflows, \(x) parse_and_write(path, x))
  commit_workflows(path, workflows)
}

parse_and_write <- function(path, workflow) {
  wf <- readLines(workflow)
  newf <- readLines(fs::path_file(workflow))
  # setup lines
  idx <- get_setup_lines(wf)
  newdx <- get_setup_lines(newf)
  res <- replace_lines(wf, idx, newf[newdx])
  # output lines
  idx <- grep("set-output name=count", res, fixed = TRUE)
  newdx <- grep("GITHUB_OUTPUT", newf)
  res[idx] <- newf[newdx]

  writeLines(res, workflow)
}

get_setup_lines <- function(wf) {
  idx <- grep("name: Set up R$", wf) + 0:10 # we expect the setup step to be ~5 lines
  steps <- seq(which(wf[idx] == "")[[1]] - 1L) 
  idx[steps]
}

get_output_line <- function(wf) {
  grep("set-output name=count", wf, fixed = TRUE)
}

replace_lines <- function(wf, idx, new) {
  start <- seq(idx[1] - 1L)
  end <- seq(idx[length(idx)], length(wf))
  c(wf[start], new, wf[end])
}


# MAIN FUNCTION: this will do a few things:
#
# 1. check out the patch branch from the repository
# 2. apply the patch using one of the three strategies outlined in the README
# 3. commit the change, push the branch, and make a pull request using the
#    gh cli application
#   returns the name of the HEAD branch on github
create_patch <- function(repodir) {
  old <- checkout_branch(repodir)
  # apply patch will fail for many repositories
  status <- apply_patch(repodir)
  # when this fails, we try to apply the workflows directly
  if (inherits(status, "error")) {
    status <- apply_workflows(repodir)
  }
  if (inherits(status, "error")) {
    return(list(status = status, head = old))
  }
  status <- push(repodir)
  return(list(status = status, head = old))
}

patch_and_report <- function(x) {
  Sys.sleep(2)
  name <- fs::path_split(x)[[1]]
  name <- fs::path(paste(name[length(name) - 1:0], collapse = "/"))
  message("-------------------------")
  message(sprintf("RUNNING %s", name))
  res <- tryCatch(create_patch(x), error = function(e) e)
  if (inherits(res$status, "error")) {
    message(sprintf("ERROR in %s: %s", name, res$status$stderr))
    message("resetting repository")
    delete_branch(x, res$head)
    return(res)
  } else {
    message(sprintf("     PR for %s successfully submitted!", name))
    fs::dir_delete(x)
    return(res)
  }
}

pr_submitted <- function(x) {
  identical(x$status$status, 0L)
}

get_pr_url <- function(x) {
  paste(trimws(x$status$stdout), "    ")
} 

record_prs <- function(x) {
  purrr::keep(x, pr_submitted) |>
    purrr::map_chr(get_pr_url) |>
    cat(file = "pull-log.md", sep = "\n", append = TRUE)
}

is_workflow_problem <- function(x) {
  inherits(x$status, "error") &&
    is.null(x$status$status) && 
    !is.null(x$status$message) &&
    x$status$message == "No workflow directory"
}

is_other_problem <- function(x) {
  is.null(x$status$status) && 
    is.null(x$status$message)
}

is_shell_problem <- function(x) {
  inherits(x$status, "error") &&
    !is.null(x$status$status) 
}

record_problems <- function(x) {
  workflows <- purrr::keep(x, is_workflow_problem)
  shell     <- purrr::keep(x, is_shell_problem)
  other     <- purrr::keep(x, is_other_problem)
  success   <- purrr::keep(x, pr_submitted)
  pct       <- sum(lengths(list(workflows, shell, other, success)))/length(x)
  msg <- "wkflow:\t%d\nshell:\t%d\nother:\t%d\nok:\t%d\n---------\ntotal:\t%d (%.2f%%)"
  msg <- sprintf(msg, 
    length(workflows), 
    length(shell), 
    length(other), 
    length(success), length(x), pct*100)
  message(msg)
  list(workflows = workflows, shell = shell, other = other)
}
