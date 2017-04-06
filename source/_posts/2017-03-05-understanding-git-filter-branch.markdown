---
layout: post
title: "Understanding git filter-branch and the git storage model"
date: 2017-03-05 10:56:59 -0800
comments: true
categories: programming
---

The other day [Steve] wanted git alchemy done on the Rust repo.

Specifically, he wanted the reference and nomicon moved out into
their [own][ref] [repositories][nom], preserving history. Both situations had some interesting
quirks, the reference has lived in `src/doc/reference/*` and `src/doc/reference.md`,
and the nomicon has lived in `src/doc/nomicon`, `src/doc/tarpl`, and at the top level
in a separate git root.

As you can guess from the title of this post, the correct tool for this job is `git filter-branch`.
[My colleague Greg][gps] calls it "the swiss-army knife of Git history rewriting".

I had some fun with filter-branch that day, thought I'd finally write an accessible tutorial for it. A lot
of folks treat filter-branch like rebase, but it isn't, and this crucial difference can lead to many
false starts. It certainly did for me back when I first learned it.

This kind of ties into the common bit of pedantry about the nature of a commit I keep seeing pop up:

> [Git commits appear to be diffs, but they're actually file copies, but they're actually ACTUALLY diffs.][pedant]


 [Steve]: http://twitter.com/steveklabnik
 [gps]: https://twitter.com/indygreg
 [ref]: https://github.com/rust-lang-nursery/reference
 [nom]: https://github.com/rust-lang-nursery/nomicon
 [pedant]: https://twitter.com/ManishEarth/status/837203953926352896

## So what is a git commit?

Generally we interact with git commits via `git show` or by looking at commits on
a git GUI / web UI. Here, we see diffs. It's natural to think of a commit as a diff,
it's the model that makes the most sense for the most common ways of interacting
with commits. It also makes some sense from an implementation point of view, diffs
seem like an efficient way of storing things.

It turns out that the "real" model is not this, it's actually that each commit
is a snapshot of the whole repo state at the time.

But actually, it isn't, the underlying implementation does make use of deltas
in packfiles and some other tricks like copy-on-write forking.

Ultimately, arguing about the "real" mental model is mostly pedantry. There are
multiple ways of looking at a commit. The documentation tends to implicitly think
of them as "full copies of the entire file tree", which is where most
of the confusion about `filter-branch` comes from. But often it's important
to picture them as diffs, too.

Understanding the implementation can be helpful, especially when you break the
repository whilst doing crazy things (I do this often). I've explained how it works
in a later section, it's not really a prerequisite for understanding filter-branch,
but it's interesting.


## How do I rewrite history with `git rebase`?

This is where some of the confusion around `filter-branch` stems from. Folks have worked with
`rebase`, and they think `filter-branch` is a generalized version of this. They're actually quite
different.

For those of you who haven't worked with `git rebase`, it's a pretty useful way of rewriting
history, and is probably what you should use when you want to rewrite history, especially for
maintaining clean git history in an unmerged under-review branch.


Rebase does a whole bunch of things. Its core task is, given the current branch and a branch that
you want to "rebase onto", it will take all commits unique to your branch, and apply them in order
to the new one. Here, "apply" means "apply the diff of the commit, attempting to resolve any conflicts".
At times, it may ask you to manually resolve the conflicts, using the same tooling
you use for conflicts during `git merge`.

Rebase is much more powerful than that, though. `git rebase -i` will open up "interactive rebase",
which will show you the commits that are going to be rebased. In this interface, you can reorder
commits, mark them for edits (wherein the rebase will stop at that commit and let you `git commit
--amend` changes into it), and even "squash" commits which lets you mark a commit to be absorbed
into the previous one. This is rather useful for when you're working on a feature and want to keep
your commits neat, but also want to make fixup patches to older commits. [Filippo's `git fixup` alias][fixup]
packages this particular task into a single git command. Changing `EDITOR=true` into
`EDITOR=: GIT_SEQUENCE_EDITOR=:` will make it not even open the editor for confirmation
and try to do the whole thing automatically.

`git rebase -x some_command` is also pretty neat, lets you run a shell command on each step during a rebase.

In this model, you are fundamentally thinking of commits as diffs. When you move around
commits in the interactive rebase editor, you're moving around diffs. When you mark things
for squashing, you're basically merging diffs. The whole process is about taking a set of
diffs and applying them to a different "base commit".

{% img center /images/post/memes/diffs-everywhere.jpg 400 %}


 [fixup]: https://blog.filippo.io/git-fixup-amending-an-older-commit/


## How do I rewrite history with `git filter-branch`?

`filter-branch` does _not_ work with diffs. You're working with the "snapshot" model
of commits here, where each commit is a snapshot of the tree, and rewriting these commits.

What `git filter-branch` will do is for each commit in the specified branch, apply filters to the
snapshot, and create a new commit. The new commit's parent will be the filtered version of the old
commit's parent. So it creates a parallel commit DAG.

Because the filters apply on the snapshots instead of the diffs, there's no chance for this to cause
conflicts like in git rebase. In git rebase, if I have one commit that makes changes to a file, and
I change the previous commit to just remove the area of the file that was changed, I'd have a conflict
and git would ask me to figure out how the changes are supposed to be applied.

In git-filter-branch, if I do this, it will just power through. Unless you explicitly write
your filters to refer to previous commits, the new commit is created in isolation, so it doesn't
worry about changes to the previous commits. If you had indeed edited the previous commit,
the new commit will appear to undo those changes and apply its own on top of that.

`filter-branch` is generally for operations you want to apply pervasively to a repository. If
you just want to tweak a few commits, it won't work, since future commits will appear to undo
your changes. `git rebase` is for when you want to tweak a few commits.

So, how do you use it?

The basic syntax is `git filter-branch <filters> branch_name`. You can use `HEAD` or `@`
to refer to the current branch instead of explicitly typing `branch_name`.

A very simple and useful filter is the subdirectory filter. It makes a given subdirectory
the repository root. You use it via `git filter-branch --subdirectory-filter name_of_subdir @`.
This is useful for extracting the history of a folder into its own repository.

Another useful filter is the tree filter, you can use it to do things like moving around, creating,
or removing files. For example, if you want to move `README.md` to `README` in the entire history,
you'd do something like `git filter-branch --tree-filter 'mv README.md README' @` (you can also
achieve this much faster with some manual work and `rebase`). The tree filter will work by checking
out each commit (in a separate temporary folder), running your filter on the working directory,
adding any changes to the index (no need to `git add` yourself), and committing the new index.

The `--prune-empty` argument is useful here, as it removes commits which are now empty due to the
rewrite.

Because it is checking out each commit, this filter is quite slow. When I initially was trying to
do Steve's task on the rust repo, I wrote a long tree filter and it was taking forever.

The faster version is the index filter. However, this is a bit trickier to work with (which is why I
tend to use a tree filter if I can get away with it). What this does is operate on the index,
directly.

The "index" is basically where things go when you `git add` them. Running `git add` will create
temporary objects for the added file, and modify the WIP index (directory tree) to include a
reference to the new file or change an existing file reference to the new one. When you commit, this
index is packaged up into a commit and stored as an object. (More on how these objects work in a
later section)

Now, since this deals with files that are already stored as objects, git doesn't need to unwrap
these objects and create a working directory to operate on them. So, with `--index-filter`, you
can operate on these in a much faster way. However, since you don't have a working directory,
stuff like adding and moving files can be trickier. You often have to use `git update-index`
to make this work.

However, a useful index filter is one which just scrubs a file (or files) from history:

```sh
$ git filter-branch --index-filter 'git rm --cached --ignore-unmatch filename' HEAD
```

The `--ignore-unmatch` makes the command still succeed if the file doesn't exist. `filter-branch`
will fail if one of the filters fails. In general I tend to write fallible filters like
`command1 1>&2 2>/dev/null ; command2 1>&2 2>/dev/null ; true`, which makes it always succeed
and also ignores any stdout/stderr output (which tends to make the progress screen fill up fast).

The `--cached` argument on `git rm` makes it operate only on the index, not the working directory.
This is great, because we don't _have_ a working directory right now.

I rarely use `git update-index` so I'm not really going to try and explain how it can be used here.
But if you need to do more complex operations in an index filter, that's the way to go.

There are many other filters, like `--commit-filter` (lets you discard a commit entirely),
`--msg-filter` (rewriting commit messages), and `--env-filter` (changing things like author metadata
or other env vars). You can see a complete list with examples [in the docs][man-git-filter-branch]


 [man-git-filter-branch]: https://git-scm.com/docs/git-filter-branch

## How did I perform the rewrites on the reference and nomicon?

For the Rust Reference, basically I had to extract the history of `src/doc/reference.md`,
AND `src/doc/reference/*` (`reference.md` was split up into `reference/*.md` recently) into
its own commit. This is an easy tree filter to write, but tree filters take forever.

Instead of trying my luck with an index filter, I decided to just make it so that the
tree filter would be faster. I first extracted `src/doc/`:

```sh
$ git filter-branch -f --prune-empty --subdirectory-filter src/doc @
```

Now I had a branch that contained only the history of `src/doc`, with the root directory moved to
`doc`. This is a much smaller repo than the entirety of Rust.

Now, I moved `reference.md` into `reference/`:

```sh
$ git filter-branch -f --prune-empty --tree-filter 'mkdir -p reference; mv reference.md reference 1>/dev/null 2>/dev/null; true' @
```

As mentioned before, the `/dev/null` and `true` bits are because the mv command will fail in some cases
(when reference.md doesn't exist), and I want it to just continue without complaining when that happens.
I only care about moving instances of that file, if that file doesn't exist there it's still okay.

Now, everything I cared about was within `reference`. The next step was simple:

```sh
$ git filter-branch -f --prune-empty --subdirectory-filter reference @
```

The whole process took maybe 10 minutes to run, most of the time being spent by the second command.
The final result can be found [here][ref].

For the nomicon, the task was easier. In the case of the nomicon, it has always resided in
`src/doc/nomicon`, `src/doc/tarpl`, or at the root. This last bit is interesting, when
[Alexis][Gankro] was working on the nomicon, he started off by hacking on it in a separate repo, but
then within that repo moved it to `src/doc/tarpl`, and performed a merge commit with rustc. There's
no inherent restriction in Git that all merges must have a common ancestor, and you can do stuff
like this. I was [quite surprised][twitterz] when I saw this, since it's pretty uncommon in general,
but really, many projects of that size will have stuff like this. Servo and html5ever do too, and usually
it's when a large project is merged into it after being developed on the side.

This sounds complicated to work with, but it wasn't that hard. I took the same subdirectory-filtere'd
doc directory branch used for the reference. Then, I renamed `tarpl/` to `nomicon/` via a tree filter,
and ran another subdirectory filter:

```sh
$ git filter-branch -f --prune-empty --tree-filter 'mv tarpl nomicon 1>/dev/null 2>/dev/null; true' @
$ git filter-branch -f --prune-empty --subdirectory-filter nomicon @
```

Now, I had the whole history of the nomicon in the root dir. Except for the commits made by Alexis
before his frankenmerge, because these got removed in the first subdirectory filter (the commits
were operating outside of `src/doc`, even though their contents eventually got moved there).

But, at this stage, I already had a branch with the nomicon at the root. Alexis' original commits
were also operating on the root directory. I can just rebase here, and the diffs of my commits will
cleanly apply!

I found the commit ([`a54e64`][a54e64]) where everything was moved to `tarpl/`, and took its parent
([`c7919f`][c7919f]). Then, I just ran `git rebase --root c7919f`, and everything cleanly rebased.
As expected, because I had a history going back to the first child of [`a54e64`][a54e64] with files
moved, and [`a54e64`][a54e64] itself only moved files, so the diffs should cleanly apply.


The final result can be found [here][nom].


 [Gankro]: http://twitter.com/Gankro/
 [twitterz]: https://twitter.com/ManishEarth/status/837441118753062912
 [a54e64]: https://github.com/rust-lang/rust/commit/a54e64b3c41103c4f6ab840d8ddd3a56ec6b5da8
 [c7919f]: https://github.com/rust-lang/rust/commit/c7919f2d9835578321bf7556ad1a01fa42e8a7e8

## Appendix: How are commits actually stored?

The way the actual implementation of a commit works is that each file being stored is hashed and
stored in a compressed format, indexed by the hash. A directory ("tree") will be a list of hashes, one for
each file/directory inside it, alongside the filenames and other metadata. This list will be hashed
and used everywhere else to refer to the directory.

A commit will reference the "tree" object for the root directory via its hash.

Now, if you make a commit changing some files, most of the files will be unchanged. So will most of
the directories. So the commits can share the objects for the unchanged files/directories, reducing
their size. This is basically a copy-on-write model. Furthermore, there's a second optimization
called a "packfile", wherein instead of storing a file git will store a delta (a diff) and a
reference to the file the diff must be applied to.

We can see this at work using `git cat-file`. `cat-file` lets you view objects in
the "git filesystem", which is basically a bunch of hash-indexed objects stored in
`.git/objects`. You can view them directly by traversing that directory (they're
organized as a trie), but `cat-file -p` will let you pretty-print their contents
since they're stored in a binary format.

I'm working with [the repo for the Rust Book][bookrepo],
playing with commit [`4822f2`][bookcommit]. It's a commit that changes
just one file (`second-edition/src/ch15-01-box.md `), perfect.

```sh
$ git show 4822f2baa69c849e4fa3b85204f219a16bde2f42
commit 4822f2baa69c849e4fa3b85204f219a16bde2f42
Author: Jake Goulding <...>
Date:   Fri Mar 3 14:07:24 2017 -0500

    Reorder sentence about a generic cons list.

diff --git a/second-edition/src/ch15-01-box.md b/second-edition/src/ch15-01-box.md
index 14c5533..29d8793 100644
--- a/second-edition/src/ch15-01-box.md
+++ b/second-edition/src/ch15-01-box.md
(diff omitted)

$ git cat-file -p 4822f2baa69c849e4fa3b85204f219a16bde2f42

tree ec7cd2821d4bcbafe08f3eca6ea60487bfdc1b52
parent 24cd100e061bb11c3f7f3219467d6d644c50d811
author Jake Goulding <...> 1488568044 -0500
committer GitHub <noreply@github.com> 1488568044 -0500

Reorder sentence about a generic cons list.
```

This tells us that the commit is a thing with some author information, a pointer to
a parent, a commit message, and a "tree". What's this tree?

```sh
$ git cat-file -p ec7cd2821d4bcbafe08f3eca6ea60487bfdc1b52
100644 blob 4cab1f4d267628ab5f4f7c14b1b64a9d4b032409    .gitattributes
040000 tree e1dcc1c754d72450b03542b2106fcb67c78805ff    .github
100644 blob 4c699f440ac134c577cb6f67b04ec5b93c652440    .gitignore
100644 blob e86d887d84a839417c960faf877c9057a8dc6823    .travis.yml
100644 blob 7990f2738876fc0fbc2ca30f5f91e91745b0b8eb    README.md
040000 tree 17b33cb52a5abb67ff678a03e7ed88cf9f163c69    ci
040000 tree 0ffd2c1238345c1b0e99af6c1c618eee4a0bab58    first-edition
100644 blob 5d1d2bb79e1521b28dd1b8ff67f9b04f38d83620    index.md
040000 tree b7160f7d05d5b5bfe28bad029b1b490e310cff22    redirects
040000 tree d5672dd9ef15adcd1527813df757847d745e299a    second-edition
```

This is just a directory! You can see that each entry has a hash. We can use
`git cat-file -p` to view each one. Looking at a `tree` object will just give
us a subdirectory, but the `blob`s will show us actual files!

```sh
$ git cat-file -p 7990f2738876fc0fbc2ca30f5f91e91745b0b8eb # Show README
# The Rust Programming Language

[![Build Status](https://travis-ci.org/rust-lang/book.svg?branch=master)](https://travis-ci.org/rust-lang/book)

To read this book online, visit [rust-lang.github.io/book/][html].

(rest of file omitted)
```

So how does this share objects? Let's look at the previous commit:

```sh
$ git cat-file -p 4822f2baa69c849e4fa3b85204f219a16bde2f42^ # `^` means "parent"
tree d219be3c5010f64960ddb609a849fc42a01ad31b
parent 21c063868f9d7fb0fa488b6f1124262f055d275b
author steveklabnik <...> 1488567224 -0500
committer steveklabnik <...> 1488567239 -0500

mdbook needs to be on the PATH for deploy

$ git cat-file -p d219be3c5010f64960ddb609a849fc42a01ad31b # the tree
100644 blob 4cab1f4d267628ab5f4f7c14b1b64a9d4b032409    .gitattributes
040000 tree e1dcc1c754d72450b03542b2106fcb67c78805ff    .github
100644 blob 4c699f440ac134c577cb6f67b04ec5b93c652440    .gitignore
100644 blob e86d887d84a839417c960faf877c9057a8dc6823    .travis.yml
100644 blob 7990f2738876fc0fbc2ca30f5f91e91745b0b8eb    README.md
040000 tree 17b33cb52a5abb67ff678a03e7ed88cf9f163c69    ci
040000 tree 0ffd2c1238345c1b0e99af6c1c618eee4a0bab58    first-edition
100644 blob 5d1d2bb79e1521b28dd1b8ff67f9b04f38d83620    index.md
040000 tree b7160f7d05d5b5bfe28bad029b1b490e310cff22    redirects
040000 tree d48b2e06970cf3a6ae65655c340922ae69723989    second-edition
```

If you look closely, all of these hashes are the same, _except_ for the hash for `second-edition`.
For the hashes which are the same, these objects are being shared across commits. The differing hash
is `d5672d` in the newer commit, and `d48b2e` in the older one.

Let's look at the objects:

```sh
$ git cat-file -p d5672d
100644 blob 82dc67a6b08f0eb62420e4da3b3aa9c0dc10911a    CONTRIBUTING.md
100644 blob 5cd51aa43f05416996c4ef055df5d6eb58fbe737    Cargo.lock
100644 blob 7ab2575fa5bf4abf6eaf767c72347580c9f769dd    Cargo.toml
100644 blob 96e9f0458b55a4047927de5bf04ceda89d772b2b    LICENSE-APACHE
100644 blob 5a56e6e8ed1909b4e4800aa8d2a0e7033ab4babe    LICENSE-MIT
100644 blob be1135fc6d28eca53959c7fc9ae191523e4bc96f    book.json
100644 blob 1400454f36840e916a7d7028d987c42fcb31b4db    dictionary.txt
100644 blob 5103c84d034d6e8a0e4b6090453ad2cdcde21537    doc-to-md.sh
040000 tree 6715d1d4c97e3d17a088922f687b8d9ffacb5953    dot
100644 blob f9e045c4c1824520534270a2643ebe68311503b8    nostarch.sh
040000 tree f8d9a9452b4bbaeba256b95d40b303cd5fb20a64    nostarch
100644 blob 0a2d16852c11355ef9d8758a304b812633dcf03c    spellcheck.sh
040000 tree 3f8db396566716299330cdd5f569fb0a0c4615dd    src
100644 blob 56677811f451084de7c3a2478587a09486209b14    style-guide.md
040000 tree 7601821a2ff38906332082671ea23e4074464dd2    tools

$ git cat-file -p d48b2e
100644 blob 82dc67a6b08f0eb62420e4da3b3aa9c0dc10911a    CONTRIBUTING.md
100644 blob 5cd51aa43f05416996c4ef055df5d6eb58fbe737    Cargo.lock
100644 blob 7ab2575fa5bf4abf6eaf767c72347580c9f769dd    Cargo.toml
100644 blob 96e9f0458b55a4047927de5bf04ceda89d772b2b    LICENSE-APACHE
100644 blob 5a56e6e8ed1909b4e4800aa8d2a0e7033ab4babe    LICENSE-MIT
100644 blob be1135fc6d28eca53959c7fc9ae191523e4bc96f    book.json
100644 blob 1400454f36840e916a7d7028d987c42fcb31b4db    dictionary.txt
100644 blob 5103c84d034d6e8a0e4b6090453ad2cdcde21537    doc-to-md.sh
040000 tree 6715d1d4c97e3d17a088922f687b8d9ffacb5953    dot
100644 blob f9e045c4c1824520534270a2643ebe68311503b8    nostarch.sh
040000 tree f8d9a9452b4bbaeba256b95d40b303cd5fb20a64    nostarch
100644 blob 0a2d16852c11355ef9d8758a304b812633dcf03c    spellcheck.sh
040000 tree f9fc05a6ff78b8211f4df931ed5e32c937aba66c    src
100644 blob 56677811f451084de7c3a2478587a09486209b14    style-guide.md
040000 tree 7601821a2ff38906332082671ea23e4074464dd2    tools
```

Again, these are the same, except for that of `src`. `src` has a _lot_ of files in it,
which will clutter this post, so I'll run a diff on the outputs of `cat-file`:

```udiff
$ diff -U5 <(g cat-file -p f9fc05a6ff78b8211f4df931ed5e32c937aba66c) <(g cat-file -p 3f8db396566716299330cdd5f569fb0a0c4615dd)
--- /dev/fd/63  2017-03-05 11:58:22.000000000 -0800
+++ /dev/fd/62  2017-03-05 11:58:22.000000000 -0800
@@ -63,11 +63,11 @@
 100644 blob ff6b8f8cd44f624e1239c47edda59560cdf491ae   ch14-02-publishing-to-crates-io.md
 100644 blob c53ef854a74b6c9fbd915be1bf824c6e78439c42   ch14-03-cargo-workspaces.md
 100644 blob 3fb59f9cc85b6b81994e83a34d542871a260a8f0   ch14-04-installing-binaries.md
 100644 blob e1cd1ca779fdf202af433108a8af6eda317f2717   ch14-05-extending-cargo.md
 100644 blob 3173cc508484cc447ebe42a024eac7d9e6c2ddcd   ch15-00-smart-pointers.md
-100644 blob 14c5533bb3b604c6e6274db278d1e7129f78d55d   ch15-01-box.md
+100644 blob 29d87933d6832374b87d98aa5588e09e0c1a4991   ch15-01-box.md
 100644 blob 47b35ed489d63ce6a885289fec01b7b16ba1afea   ch15-02-deref.md
 100644 blob 2d20c55cc8605c0c899bc4867adc6b6ea1f5c902   ch15-03-drop.md
 100644 blob 8e3fcf4e83fe1ce985a7c0b479b8b16701765aaf   ch15-04-rc.md
 100644 blob a4ade4ae8bf5296d79ed51d69506e71a83f9f489   ch15-05-interior-mutability.md
 100644 blob 3a4db5616c4f5baeb95d04ea40c6747e60181684   ch15-06-reference-cycles.md
 ```

As you can see, only the file that was changed in the commit has a new blob stored.
If you view `14c553` and `29d879` you'll get the pre- and post- commit versions
of the file respectively.


So basically, each commit stores a tree of references to objects, often sharing nodes
with other commits.

I haven't had the opportunity to work with packfiles much, but they're an
additional optimization on top of this. [Aditya's post][chimera] is a good
intro to these.



 [bookrepo]: https://github.com/rust-lang/book
 [bookcommit]: 4822f2baa69c849e4fa3b85204f219a16bde2f42
 [chimera]: https://codewords.recurse.com/issues/three/unpacking-git-packfiles

