setup_tmpdir <- function() {
  tmp <- fs::file_temp()
  fs::dir_create(tmp)
  tmp
}

setup_repodir <- function(org, repo, tmpdir) {
  fs::dir_create(fs::path(tmpdir, org, repo), recurse = TRUE)
}

get_repository <- function(lesson, tmpdir) {
  path <- setup_repodir(lesson$carpentries_org, lesson$repo, tmpdir)
  gert::git_clone(lesson$repo_url, path = path)
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
  tryCatch({
    processx::run("gh", 
      c("pr", "create",
        "--title", "urgent: fix workflows", 
        "--body", gert::git_log(repo = path, max = 1)$message), 
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
  current <- tools::md5sum(workflows)
  names(current) <- fs::path_file(names(current))
  if (all(current == sha)) {
    copy_and_commit(path, workflows)
  } else {
    # read in the workflows and modify accordingly
    parse_and_commit(path, workflows)
  }
}

commit_workflows <- function(path, workflows) {
  to_add <- fs::path(".github/workflows", fs::path_file(workflows))
  gert::git_add(to_add, repo = path)
  # I am committing like this so that my signature is added
  tryCatch({
    processx::run("git", c("commit", "-m", 
      "use up-to-date r-lib action; update GHA syntax\n\nsee https://github.com/carpentries/styles/issues/641 for details"), 
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
  idx <- get_output_line(res)
  newdx <- get_output_line(newf)
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
create_patch <- function(repodir) {
  old <- checkout_branch(repodir)
  status <- apply_patch(repodir)
  nosha <- grepl("error: sha1 information is lacking or useless", 
    status$stderr, fixed = TRUE)
  if (nosha) {
    apply_workflows(repodir)
  }
  push(repodir)
}
