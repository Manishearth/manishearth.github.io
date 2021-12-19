---
layout: post
title: "The future of Clippy"
date: 2018-06-05 14:42:24 -0700
comments: true
categories: rust programming
---

We've recently been making lots of progress on future plans for [clippy] and I
thought I'd post an update.

For some background, Clippy is the linter for Rust. We have more than 250 lints, and
are steadily growing.

## Clippy and Nightly

Sadly, Clippy has been nightly-only for a very long time. The reason behind this is
that to perform its analyses it hooks into the compiler so that it doesn't have to
reimplement half the compiler's info to get things like type information. But
these are internal APIs and as such will never stabilize, so Clippy needs to be
used with nightly Rust.

We're hoping this will change soon! The plan is that Clippy will eventually
be distributed by Rustup, so something like `rustup component add clippy` will
get you the clippy binary.

The first steps are [happening], we're planning on setting it up so that when it compiles
Rustup will be able to fetch a clippy component (however this won't be the recommended way
to use clippy until we figure out the workflow here, so sit tight!)

Eventually, clippy will probably block nightlies[^1]; and after a bunch of cycles of letting that
work itself out, hopefully clippy will be available with the stable compiler. There's a lot of
stuff that needs to be figured out, and we want to do this in a way that minimally impacts
compiler development, so this may move in fits and starts.

 [happening]: https://github.com/rust-lang/rust/pull/51122

## Lint audit

A couple months ago [Oliver] and I[^2] did a [lint audit] in Clippy. Previously,
clippy lints were classified as simply "clippy", "clippy_pedantic", and "restriction".
"restriction" was for allow-by-default lints for things which are generally not a problem but may
be something you specifically want to forbid based on the situation, and "pedantic"
was for all the lints which were allow-by-default for other reasons.

Usually these reasons included stuff like "somewhat controversial lint", "lint is very buggy",
or for lints which are actually exceedingly pedantic and may only be wanted by folks
who very seriously prefer their code to be _perfect_.


We had a lot of buggy lints, and these categories weren't as helpful. People use clippy
for different reasons. Some folks only care about clippy catching bugs, whereas others want
its help enforcing the general "Rust Style".

So we came up with a better division of lints:

 - Correctness (Deny): Probable bugs, e.g. calling `.clone()` on `&&T`, which clones the (`Copy`) reference and not the actual type
 - Style (Warn): Style issues; where the fix usually doesn't semantically change the code. For example, having a method named `into_foo()` that doesn't take `self` by-move
 - Complexity (Warn): For detecting unnecessary code complexities and helping simplify them. For example, replacing `.filter(..).next()` with `.find(..)`
 - Perf (Warn): Detecting potential performance footguns, like using `Box<Vec<T>>` or calling `.or(foo())` instead of `or_else(foo)`.
 - Pedantic (Allow): Controversial or exceedingly pedantic lints
 - Nursery (Allow): For lints which are buggy or need more work
 - Cargo (Allow): Lints about your Cargo setup
 - Restriction (Allow): Lints for things which are not usually a problem, but may be something specific situations may dictate disallowing.

and applied it to the codebase. You can see the results on our [lint list]

Some lints could belong in more than one group, and we picked the best one in that case. Feedback welcome!

## Clippy 1.0

In the run up to making Clippy a rustup component we'd like to do a 1.0 release of Clippy. This involves an RFC,
and pinning down an idea of stability.

The general plan we have right now is to have the same idea of lint stability as rustc; essentially
we do not guarantee stability under `#[deny(lintname)]`. This is mostly fine since `deny` only affects
the current crate (dependencies have their lints capped) so at most you'll be forced to slap on an `allow`
somewhere after a rustup.

With specifics, this means that we'll never remove lints. We may recategorize them, or "deprecate" them
(which makes the lint do nothing, but keeps the name around so that `#[allow(lintname)]` doesn't break the build
aside from emitting a warning).

We'll also not change what individual lints do fundamentally. The kinds of changes you can expect are:

 - Entirely new lints
 - Fixing false positives (a lint may no longer lint in a buggy case)
 - Fixing false negatives (A case where the lint _should_ be linting but doesn't is fixed)
 - Bugfixes (When the lint panics or does something otherwise totally broken)

When fixing false negatives this will usually be fixing things that can be understood as comfortably within the
scope of the lint as documented/named

I'll be posting an RFC soonish that both contains this general plan of stability, as well as a list of the current
lint categorization for folks to discuss.

--------


Anyway, thought I'd just post a general update on everything, since stuff's changing quickly.

There's still time for stable or even just reliably rustuppable nightly clippy to happen but the path to it is pretty clear now!


 [^1]: As in, if clippy is broken there will not be a nightly that day. Rustfmt and RLS work this way right now AIUI.
 [clippy]: https://github.com/rust-lang-nursery/rust-clippy
 [lint audit]: https://github.com/rust-lang-nursery/rust-clippy/pull/2579
 [^2]: Okay, mostly Oliver
 [Oliver]: https://github.com/oli-obk
 [lint list]: https://rust-lang-nursery.github.io/rust-clippy/master/index.html