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

The good thing about this is that it will preserve history and will prevent a
merge conflict because these will be part of the history.

This is what a merge with styles looks like after the patch has been applied
(with an unrelated merge conflict) in the instructor training repository.

NOTE: The last time styles was updated was back in February:

```
(gh-pages)$ git log --pretty=reference | grep styles | head -1
fd95778e (Merge branch 'gh-pages' of github.com:carpentries/styles into upgrade-template, 2022-02-01)
```

This is what things look like when we apply the patch:

```
(gh-pages)$ git switch -c test-updates
(test-updates)$ git am -3 ../2022-10-20-workflow-bug/workflow.patch
Applying: use up-to-date r-lib action
Applying: switch to new output command
```

After these updates were made, I run the update for styles:

```
(test-updates)$ git pull https://github.com/carpentries/styles
remote: Enumerating objects: 85, done.
remote: Counting objects: 100% (85/85), done.
remote: Compressing objects: 100% (36/36), done.
remote: Total 85 (delta 56), reused 68 (delta 48), pack-reused 0
Unpacking objects: 100% (85/85), 25.52 KiB | 1.21 MiB/s, done.
From https://github.com/carpentries/styles
 * branch              HEAD       -> FETCH_HEAD
Auto-merging _layouts/base.html
CONFLICT (content): Merge conflict in _layouts/base.html
Auto-merging bin/boilerplate/_config.yml
Automatic merge failed; fix conflicts and then commit the result.
```

There was a conflict, but when we look at it, the conflict has do to with
modifications that the trainers made in one of the template files and NOT with
the patch we just made:

```
(test-updates)$ git diff
diff --cc _layouts/base.html
index 7536c245,67b6d7af..00000000
--- a/_layouts/base.html
+++ b/_layouts/base.html
@@@ -31,15 -29,10 +31,18 @@@
        <script src="https://oss.maxcdn.com/html5shiv/3.7.2/html5shiv.min.js"></script>
        <script src="https://oss.maxcdn.com/respond/1.4.2/respond.min.js"></script>
        <![endif]-->
 -
 -  <title>
 +      <title>
    {% if page.title %}{{ page.title }}{% endif %}{% if page.title and site.title %} &ndash; {% endif %}{% if site.title %}{{ site.title }}{% endif %}
    </title>
++<<<<<<< HEAD
 +
 +    <meta property="og:url" content="{{ page.root }}/{{ page.url }}" />
 +<meta property="og:type" content="article" />
 +<meta property="og:title" content="{{ page.title }}" />
 +<meta property="og:description" content="Lesson episode summary - keypoints?" />
 +<meta property="og:image" content="http://christinalk.github.io/instructor-training/assets/img/swc-icon-blue.svg" />
++=======
++>>>>>>> b31b489624a25fa7f76513047056953f3e649b61
  
    </head>
    <body>
```

And of course to clean up, I abort the merge and switch back to the gh-pages branch

```
(test-updates)$ git merge --abort
(test-updates)$ git switch gh-pages
(gh-pages)$ git branch -D test-updates
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
