# REPOSITORY FUNCTIONS
#
# These functions are responsible for setting up and manipulating the
# repositories in temporary files. 

#' set up a temporary directory to store the repositories
#' @return the path of the temporary directory
setup_tmpdir <- function() {
  tmp <- fs::file_temp()
  fs::dir_create(tmp)
  tmp
}

#' provision a directory for a repository
#'
#' @param org the organisation name
#' @param repo the repository name
#' @param tmpdir, the directory provisioned by `setup_tmpdir()`
#'
#' @return the name of the new directory
setup_repodir <- function(org, repo, tmpdir) {
  the_dir <- fs::path(tmpdir, org, repo)
  fs::dir_create(the_dir, recurse = TRUE)
}

#' download a lesson repository from github
#'
#' @param lesson a list derived from a lessons feed in
#'   https://feeds.carpentries.org/. This list must have the following elements:
#'   - carpentries_org
#'   - repo
#' @param tmpdir, the directory provisioned by `setup_tmpdir()`
get_repository <- function(lesson, tmpdir) {
  path <- setup_repodir(lesson$carpentries_org, lesson$repo, tmpdir)
  msg <- sprintf("Creating %s ------------", fs::path_rel(path, start = tmpdir))
  message(msg)
  if (!fs::dir_exists(fs::path(path, ".git"))) {
    gert::git_clone(lesson$repo_url, path = path)
  }
  path
}

#' checkout a new branch in a repository
#'
#' @param path path to a repository
#' @param branch name of the branch (defaults to znk-fix-workflows-2022-10-20)
#'
#' @return the name of the current HEAD branch before the branch was fixed. 
checkout_branch <- function(path, branch = "znk-fix-workflows-2022-10-20") {
  current <- gert::git_branch(repo = path)
  if (gert::git_branch_exists(branch, repo = path)) {
    gert::git_branch_checkout(branch, repo = path)
  } else {
    gert::git_branch_create(branch, ref = "HEAD", checkout = TRUE, repo = path)
  }
  current
}

#' push updates to a new branch and create a pull request
#'
#' This will attempt to take the committed changes, push them to the origin,
#' and create a pull request using the `gh` utility. 
#'
#' @param path path to a repository
#' @param branch name of the branch (defaults to znk-fix-workflows-2022-10-20)
#' 
#' @return a list. status message from the gh utility. If it is successful, the
#'   "stdout" element will contain the URL for the PR. If it is an error, the
#'   stderr will inform you as to what happened.
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

#' delete a branch and restore the head
#'
#' @param path path to a repository
#' @param head the branch to set as HEAD
#' @param branch name of the branch to delete (defaults to znk-fix-workflows-2022-10-20)
delete_branch <- function(path, head, branch = "znk-fix-workflows-2022-10-20") {
  gert::git_branch_checkout(head, repo = path)
  gert::git_branch_delete(branch, repo = path)
}

#' Attempt to apply a patch using `git am` and a patchfile
#'
#' To avoid merge conflicts down the road, we can apply the patch that was
#' created in the upstream repository. Of course, this assumes that the
#' receiving repository has the same hash in the recieving files. This will
#' not throw an error and will abort the command if it fails.
#'
#' @param path path to a repository
#' @param path to a patchfile that can be applied
#'
#' @return a list. the status of the `git am` command. If it errors, the status
#'   will have the class "error" that you can test for with `inerits(object, "error")`
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

#' Write and commit workflow files
#'
#' If a patch is not possible, we attempt to overwrite the workflow files 
#' either wholesale or by individual steps, depending on whether or not they
#' have the same hash. 
#'
#' With either method, the changes will be applied and a single commit will be
#' made. 
#' 
#' @param path path to a git repository
#' @param md5 md5sums of the workflow files (which are expected to be in the
#'   current working directory).
#' @return a list that is either the status of the processx run or an error.
apply_workflows <- function(path, md5 = "workflow-md5.txt") {
  known <- read.table(md5)
  sha <- setNames(known[[1]], fs::path_file(known[[2]]))
  workflows <- fs::path(path, ".github/workflows/", names(sha))
  dir_exists <- fs::dir_exists(fs::path_dir(workflows[1]))
  if (dir_exists) {
    files_exist <- fs::file_exists(workflows)
    if (!any(files_exist)) {
      msg <- "No workflow files generated by The Carpentries."
      message(msg)
      return(tryCatch(stop(msg), error = function(e) e))
    }
    workflows <- workflows[files_exist]
    sha       <- sha[files_exist]
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

#' Add and commit workflow files to a repository
#'
#' This uses the system version of git because the R binding does not recognise
#' GPG signatures. This helps demonstrate the authenticity of the pull requests.
#'
#' @param path path to the repository
#' @param workflows the workflow files to add
#'
#' @return a list. this will have the class "error" if an error occured"
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


#' Copy the workflow files wholesale to the repository
#'  
#' This is Option 2 in the solution
#'
#' @param path path to the repository
#' @param workflows the workflow files to add
#'
#' @return a list. this will have the class "error" if an error occured"
copy_and_commit <- function(path, workflows) {
  ours <- fs::path_file(workflows)
  fs::file_copy(ours, workflows)
  commit_workflows(path, workflows)
}

#' Replace steps in the workflows
#'  
#' This is Option 3 in the solution
#'
#' @param path path to the repository
#' @param workflows the workflow files to add
#'
#' @return a list. this will have the class "error" if an error occured"
parse_and_commit <- function(path, workflows) {
  purrr::walk(workflows, \(x) parse_and_write(path, x))
  commit_workflows(path, workflows)
}

#' Parse and write a workflow file to replace individual steps
#'
#' @param path path to the repository
#' @param workflow the workflow file to add
#' 
#' @return this function is used for its side-effect. It will return TRUE if
#'   it successfully wrote to the file. 
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


#' Find the lines for the Set up R workflow
#'
#' @param wf lines of a workflow file
#' @return an integer vector that matches the Set up R step. 
get_setup_lines <- function(wf) {
  idx <- grep("name: Set up R$", wf) + 0:10 # we expect the setup step to be ~5 lines
  steps <- seq(which(wf[idx] == "")[[1]] - 1L) 
  idx[steps]
}

#' Replace lines in a workflow file with new lines
#'
#' @param wf lines of a workflow file
#' @param idx indices of lines to replace
#' @param new lines to insert
#' @return the lines of wf, modified with new inserted.
replace_lines <- function(wf, idx, new) {
  start <- seq(idx[1] - 1L)
  end <- seq(idx[length(idx)], length(wf))
  c(wf[start], new, wf[end])
}


#' patch and push the changes
#'
#' 1. check out the patch branch from the repository
#' 2. apply the patch using one of the three strategies outlined in the README
#' 3. commit the change, push the branch, and make a pull request using the
#'    gh cli application
#'   returns the name of the HEAD branch on github
#' @param repodir the directory to a github repository
#' @return a list. status is the output of the last run command. This may be
#'   an error or a status. head is the default branch for the repository.
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

#' Patch, Push, and Report Changes
#' 
#' If the PR was successful, the temporary repository will be deleted,
#' otherwise, the branch will be deleted and the erro reported.
#'
#' @param x the path to a repository
#' @return the output of `create_patch()`
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

# Problem recorders ------------------------------------------------------------
#
# These functions handle the output of `patch_and_report()`

# filters -----------------------------
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
    startsWith(x$status$message, "No workflow")
}

is_other_problem <- function(x) {
  is.null(x$status$status) && 
    is.null(x$status$message)
}

is_shell_problem <- function(x) {
  inherits(x$status, "error") &&
    !is.null(x$status$status) 
}

# collector --------------------------------
collect_problems <- function(x) {
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

# recorder ------------------------------------
record_problems <- function(x, db) {
  problems <- collect_problems(x)
  for (i in names(problems)) {
    this_problem <- problems[[i]]
    if (length(this_problem) == 0) {
      next
    } else {
      thing <- db[names(this_problem)]
      urls <- purrr::map_chr(thing, "repo_url")
      problem_place <- switch(i,
        shell = c("status", "sterr"),
        workflows = c("status", "message"),
        other = "message"
      )
      messages <- purrr::map_chr(this_problem, problem_place)
      the_file <- paste0(i, "-problems.md")
      cat(paste(urls, messages, sep = " --- "), sep = "    \n", file = the_file,
        append = TRUE)
    }
  }
  problems
}
