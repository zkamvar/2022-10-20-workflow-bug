setup_tmpdir <- function() {
  tmp <- fs::temp_file()
  fs::dir_create(tmp)
  tmp
}

setup_repodir <- function(org, repo, tmpdir) {
  fs::dir_create(fs::path(tmpdir, org, repo), recurse = TRUE)
}

get_repository <- function(org, repo, tmpdir) {
  path <- setup_repodir(org, repo, tmpdir)
  gert::git_clone(paste0(org, "/", repo), path = path)
  path
}

checkout_branch <- function(path, branch = "znk-fix-workflows-2022-10-20") {
  if (gert::git_branch_exists(branch, repo = path)) {
    gert::git_branch_checkout(branch, repo = path)
  } else {
    gert::git_branch_create(branch, ref = "HEAD", checkout = TRUE, repo = path)
  }
}

delete_branch <- function(path, branch = "znk-fix-workflows-2022-10-20") {
  gert::git_branch_delete(branch, repo)
}

apply_patch <- function(path, patchfile = "workflow.patch") {
  patchfile <- fs::path_abs(patchfile)
  res <- processx::run("git", c("am", "-3", patchfile), wd = path, 
    echo = TRUE, echo_cmd = TRUE)
}
