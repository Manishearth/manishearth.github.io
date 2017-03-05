---
layout: post
title: "Mitigating underhandedness: Clippy!"
date: 2017-01-21 15:22:16 -0800
comments: true
categories: programming mozilla rust
---

_This may be part of a collaborative blog post series about underhanded Rust code. Or it may not. I invite you to write your own posts about underhanded code to make it so!_

Last month we opened up [The Underhanded Rust competition][underhanded]. This contest is about
writing seemingly-innocuous malicious code; code that is deliberately written to do some harm,
but will pass a typical code review.

It is inspired by the [Underhanded C][c] contest. Most of the underhanded C submissions have to do
with hidden buffer overflows, pointer arithmetic fails, or misuse of C macros; and these problems
largely don't occur in Rust programs. However, the ability to layer abstractions on each other does
open up new avenues to introducing underhandedness by relying on sufficiently confusing abstraction
sandwiches. There are probably other interesting avenues. Overall, I'm pretty excited to see what
kind of underhandedness folks come up with!

Of course, underhandedness is not just about fun and games; we should be hardening our code against
this kind of thing. Even if you trust your fellow programmers. Even if _you_ are the sole programmer and you trust yourself.
After all, [you can't spell Trust without Rust][gankro]; and Rust is indeed about trust. Specifically,
Rust is about trusting _nobody_. Not even yourself.

{% img /images/post/memes/trust-nobody.jpg 300 %}

Rust protects you from your own mistakes when it comes to memory management. But we
should be worried about other kinds of mistakes, too. Many of the techniques used in underhanded
programming involve sleights of hand that could just as well be introduced in the code by accident, causing bugs.
Not memory safety bugs (in Rust), but still, bugs. The existence of these sleights of hand is great for
that very common situation
[when you are feeling severely under-plushied and must win a competition to replenish your supply][prize]
but we really don't want these creeping into real-world code, either by accident or intentionally.


 [underhanded]: https://underhanded.rs/blog/2016/12/15/underhanded-rust.en-US.html
 [c]: http://www.underhanded-c.org
 [gankro]: https://github.com/Gankro/thesis/blob/master/thesis.pdf
 [prize]: https://underhanded.rs/blog/2016/12/15/underhanded-rust.en-US.html#prize

----

Allow me to take a moment out of your busy underhanded-submission-writing schedules to talk to you about
our Lord and Savior [Clippy][clippy].

Clippy is for those of you who have become desensitized to the constant whining of the Rust compiler
and need a higher dosage of whininess to be kept on their toes. Clippy is for those perfectionists
amongst you who want to know every minute thing wrong with their code so that they can fix it.
But really, Clippy is for everyone.

Clippy is simply a large repository of lints. As of the time of writing this post, there are
[183 lints][lints] in it, though not all of them are enabled by default. These use the regular Rust lint
system so you can pick and choose the ones you need via `#[allow(lint_name)]` and
`#[warn(lint_name)]`. These lints cover a wide range of functions:

 - Improving readability of the code (though [rustfmt][fmt] is the main tool you should use for this)
 - Helping make the code more compact by reducing unnecessary things (my absolute favorite is [needless_lifetimes])
 - Helping make the code more idiomatic
 - Making sure you don't do things that you're not supposed to
 - Catching mistakes and cases where the code may not work as expected

The last two really are the ones which help with underhanded code. Just to give an example,
we have lints like:

 - [cmp_nan], which disallows things like `x == NaN`
 - [clone_double_ref], which disallows calling `.clone()` on double-references (`&&T`), since that's a straightforward copy and you probably meant to do something like `(*x).clone()`
 - [for_loop_over_option]: `Option<T>` is iterable, and while this is useful when composing iterators, directly iterating over an option is usually an indication of a mistake.
 - [match_same_arms], which checks for identical match arm bodies (strong indication of a typo)
 - [suspicious_assignment_formatting], which checks for possible typos with the `+=` and `-=` operators
 - [unused_io_amount], which ensures that you don't forget that some I/O APIs may not write all bytes in the span of a single call

These catch many of the gotchas that might crop up in Rust code. In fact,
I based [my solution of an older, more informal Underhanded Rust contest][reddit-uh] on one of these.


 [reddit-uh]: https://www.reddit.com/r/rust/comments/3hb0wm/underhanded_rust_contest/cu5yuhr/

## Usage

Clippy is still nightly-only. We hook straight into the compiler's guts to obtain
the information we need, and like most internal compiler APIs, this is completely unstable. This
does mean that you usually need a latest or near-latest nightly for clippy to work, and there will
be times when it won't compile while we're working to update it.

There is a plan to ship clippy as an optional component of rustc releases, which will fix all of
these issues (yay!).

But, for now, you can use clippy via:

```sh
rustup install nightly
# +nightly not necessary if nightly is your default toolchain
cargo +nightly install clippy
# in your project folder
cargo +nightly clippy
```

If you're going to be making it part of the development procedures of a crate
you maintain, you can also [make it an optional dependency][optional].

If you're on windows, there's currently a rustup/cargo [bug] where you may have to add
the rustc libs path in your `PATH` for `cargo clippy` to work.


There's an experimental project called [rustfix] which can automatically apply suggestions from
clippy and rustc to your code. This may help in clippy-izing a large codebase, but it may
also eat your code and/or laundry, so beware.

 [clippy]: http://github.com/manishearth/rust-clippy/
 [lints]: https://github.com/manishearth/rust-clippy/#lints
 [fmt]: https://github.com/rust-lang-nursery/rustfmt/
 [cmp_nan]: https://github.com/Manishearth/rust-clippy/wiki#cmp_nan
 [clone_double_ref]: https://github.com/Manishearth/rust-clippy/wiki#clone_double_ref
 [for_loop_over_option]: https://github.com/Manishearth/rust-clippy/wiki#for_loop_over_option
 [match_same_arms]: https://github.com/Manishearth/rust-clippy/wiki#match_same_arms
 [needless_lifetimes]: https://github.com/Manishearth/rust-clippy/wiki#needless_lifetimes
 [suspicious_assignment_formatting]: https://github.com/Manishearth/rust-clippy/wiki#suspicious_assignment_formatting
 [unused_io_amount]: https://github.com/Manishearth/rust-clippy/wiki#unused_io_amount
 [optional]: https://github.com/manishearth/rust-clippy/#optional-dependency
 [bug]: https://github.com/rust-lang-nursery/rustup.rs/issues/876
 [rustfix]: https://github.com/killercup/rustfix

## Contributing

There's a _lot_ of work that can be done on clippy. A hundred and eighty lints is just
a start, there are [hundreds more lint ideas filed on the issue tracker][issues]. We're
willing to mentor anyone who wants to get involved; and have
[specially tagged "easy" issues][easy] for folks new to compiler internals. In general,
contributing to clippy is a great way to gain an understanding of compiler internals
if you want to contribute to the compiler itself.

If you don't want to write code for clippy, you can also run it on random crates,
open pull requests with fixes, and file bugs on clippy for any false positives that appear.

There are more tips about contributing in [our CONTRIBUTING.md][contri].


 [issues]: https://github.com/manishearth/rust-clippy/issues
 [easy]: https://github.com/manishearth/rust-clippy/issues?q=is%3Aissue+is%3Aopen+label%3AE-easy
 [contri]: https://github.com/Manishearth/rust-clippy/blob/master/CONTRIBUTING.md

---------

I hope this helps reduce mistakes and underhandedness in your code!

..unless you're writing code for the Underhanded Rust competition. In that case, underhand away!

