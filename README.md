## Fixing a bug in The Carpentries Infrastructure 2022-10

A bug in our lesson infrastructure has reared its head and now we are facing
the consequences: <https://github.com/carpentries/styles/issues/641>

Effectively, there were two workflow steps that were pointing to an outdated
branch for a github action that set up R, which now fails to run, preventing the
workflow from running, which causes all PRs to fail and causes all R-based
lessons to fail.

Normally, when we have a bug in our infrastructure, we would make the update in
styles and then make pull requests across our infrastructure to fix them.
However, the problem with this strategy is that there are many times in which
we face merge conflicts in our pull requests. Thus, I am going to approach this
in a different way.

## Solutions

### Clean Patch

One of the good things is that these particular workflow files were last updated
2021-05-21 in [commit da771119](https://github.com/carpentries/styles/commit/da771119b6c4adc61dea3e33786a3c8179600cb1).

In theory, if a lesson had those updates, regardless of any other updates, we
can apply a patch with:

```sh
git am -3 workflow.patch
```

[The patch](workflow.patch) itself is taken from the [patch for PR 643](https://patch-diff.githubusercontent.com/raw/carpentries/styles/pull/643.patch)

The good thing about this is that it will preserve history and _hopefully_ 
prevent a merge conflict because these will be part of the history. Here is what
the patch looks like when it has already been applied in the lesson-example repo

```
(main)$ git am -3 ../2022-10-20-workflow-bug/workflow.patch
Applying: use up-to-date r-lib action
Using index info to reconstruct a base tree...
M	.github/workflows/template.yml
M	.github/workflows/website.yml
Falling back to patching base and 3-way merge...
Auto-merging .github/workflows/website.yml
Auto-merging .github/workflows/template.yml
No changes -- Patch already applied.
Applying: switch to new output command
Using index info to reconstruct a base tree...
M	.github/workflows/template.yml
M	.github/workflows/website.yml
Falling back to patching base and 3-way merge...
No changes -- Patch already applied.
```

### File Replacement

If the files have the same md5sum as [workflow-md5.txt](workflow-md5.txt), then 
we can just copy over the workflows we have stored here to update. 

This will cause a merge conflict downstream, but this situation means that a
merge conflict would have happened anyways.

### Individual line replacements

If the files do not have the same md5sum, then they were not updated and instead
we need to modify the individual lines. 

This one I do not like because these workflows are either far outdated or they
have been modified (which I know some incubator lessons have done this). My
mitigation strategy is to search for `name: Set up R$`, extract the workflow 
step by searching for blank line delimiters, and then replacing the block with
our updated setup R workflow. 
