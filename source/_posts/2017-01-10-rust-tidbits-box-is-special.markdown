---
layout: post
title: "Rust tidbits: Box is special"
date: 2017-01-10 22:59:43 -0800
comments: true
categories: mozilla rust programming tidbits
---

Rust is not a simple language. As with any such language, it has many little tidbits of complexity
that most folks aren't aware of. Many of these tidbits are ones which may not practically matter
much for everyday Rust programming, but are interesting to know. Others may be more useful. I've
found that a lot of these aren't documented anywhere (not that they always should be), and sometimes
depend on knowledge of compiler internals or history. As a fan of programming trivia myself, I've
decided to try writing about these things whenever I come across them. "Tribal Knowledge" shouldn't
be a thing in a programming community; and trivia is fun!


----------

So. `Box<T>`. Your favorite heap allocation type that nobody uses[^1].

I was discussing some stuff on the rfcs repo when
[@burdges realized that `Box<T>` has a funky `Deref` impl][rfcs-impl].

Let's [look at it][deref-impl]:

```rust
#[stable(feature = "rust1", since = "1.0.0")]
impl<T: ?Sized> Deref for Box<T> {
    type Target = T;

    fn deref(&self) -> &T {
        &**self
    }
}

#[stable(feature = "rust1", since = "1.0.0")]
impl<T: ?Sized> DerefMut for Box<T> {
    fn deref_mut(&mut self) -> &mut T {
        &mut **self
    }
}
```

Wait, what? _Squints_

```rust
    fn deref(&self) -> &T {
        &**self
    }
```

_The call is coming from inside the house!_


 [rfcs-impl]: https://github.com/rust-lang/rfcs/issues/1850#issuecomment-271766300
 [deref-impl]: https://github.com/rust-lang/rust/blob/e4fee525e04838dabc82beed5ae1a06051be53fd/src/liballoc/boxed.rs#L502
 [^1]: Seriously though, does anyone use it much? I've only seen it getting used for boxed DSTs (trait objects and boxed slices), which themselves are pretty rare, for sending heap types over FFI, and random special cases. I find this pretty interesting given that other languages are much more liberal with non-refcounted single-element allocation.


In case you didn't realize it, this deref impl returns `&**self` -- since `self`
is an `&Box<T>`, dereferencing it once will provide a `Box<T>`, and the second dereference
will dereference the box to provide a `T`. We then wrap it in a reference and return it.

But wait, we are _defining_ how a `Box<T>` is to be dereferenced (that's what `Deref::deref` is
for!), such a definition cannot itself dereference a `Box<T>`! That's infinite recursion.


And indeed. For any other type such a `deref` impl would recurse infinitely. If you run
[this code][lolbox]:

```rust
use std::ops::Deref;

struct LolBox<T>(T);

impl<T> Deref for LolBox<T> {
    type Target = T;
    fn deref(&self) -> &T {
        &**self
    }
}
```

 [lolbox]: https://play.rust-lang.org/?gist=9c8a02336c6816e57c83de39c103ca06&version=stable&backtrace=0

the compiler will warn you:

```text
warning: function cannot return without recurring, #[warn(unconditional_recursion)] on by default
 --> <anon>:7:5
  |
7 |     fn deref(&self) -> &T {
  |     ^
  |
note: recursive call site
 --> <anon>:8:10
  |
8 |         &**self
  |          ^^^^^^
  = help: a `loop` may express intention better if this is on purpose
```

Actually trying to dereference the type will lead to a stack overflow.

Clearly something is fishy here. Turns out, `Box<T>` is special.

This is partly due to historical accident.

To understand this, we must look back to Ye Olde days of pre-1.0 Rust (ca 2014). Back in these days,
we had none of this newfangled "stability" business. The compiler broke your code every two weeks.
Of course, you wouldn't _know_ that because the compiler would usually crash before it could tell
you that your code was broken! Sigils roamed the lands freely, and cargo was but a newborn child
which was destined to eventually end the tyranny of Makefiles. People were largely happy knowing
that their closures were safely boxed and their threads sufficiently green.

Back in these days, we didn't have `Box<T>`, `Vec<T>`, or `String`. We had `~T`, `~[T]`, and `~str`.
The second two are _not_ equivalent to `Box<[T]>` and `Box<str>`, even though they may look like it,
they are both growable containers like `Vec<T>` and `String`. `~` conceptually meant "owned", though
IMO that caused more confusion than it was worth.

You created a box using the `~` operator, e.g. `let x = ~1;`. It could be dereferenced with the `*`
operator, and autoderef worked much like it does today.

As a "primitive" type; like all primitive types, `~T` was special. The compiler knew things about
it. The compiler knew how to dereference it without an explicit `Deref` impl. In fact, the `Deref`
traits [came into existence][deref-pr] much after `~T` did. `~T` never got an explicit `Deref` impl,
though it probably should have. This whole situation is reminiscent of how the `Add` impls on
integers work, the impl literally [defines `Add` on two integers to be their addition][add-impl].
The reason these impls need to exist is so that people can still call `Add::add` if they need to
in generic code and be able to pass integers to things with an `Add` bound. 

Eventually, there was a move to remove sigils from the language. The box constructor `~foo` was
superseded by [placement `box` syntax][placement], which still exists in Rust nightly[^3]. Then, the
[`~T` type became `Box<T>`][die-sigil]. (`~[T]` and `~str` would also be removed, though `~str` took
a very confusing detour with `StrBuf` first).

However, `Box<T>` was still special. It no longer needed special syntax to be referred to or
constructed, but it was still internally a special type. It didn't even have a `Deref` impl yet,
that came [six months later][box-gets-deref], and it was implemented as `&**self`, exactly the same
as it is today.


 [deref-pr]: https://github.com/rust-lang/rust/pull/12491
 [add-impl]: https://github.com/rust-lang/rust/blob/e57f061be20666eb0506f6f41551c798bbb38b60/src/libcore/ops.rs#L255
 [placement]: https://github.com/rust-lang/rust/pull/11055/
 [die-sigil]: https://github.com/rust-lang/rust/pull/13904
 [box-gets-deref]: https://github.com/rust-lang/rust/pull/20052
 [^3]: It will probably eventually be replaced or made equivalent to the `<-` syntax before stabilizing

But why does it _have_ to be special now? Rust had all the features it needed (allocations,
ownership, overloadable deref) to implement `Box<T>` in pure rust in the stdlib as if it
were a regular type.

Turns out that Rust didn't. You see, because `Box<T>` and before it `~T` were special, their
dereference semantics were implemented in a different part of the code. And, these semantics were
not the same as the ones for `DerefImm` and `DerefMut`, which were created for use with other smart
pointers. I don't know if the possibility of being used for `~T` was considered when
`DerefImm`/`DerefMut` were being implemented, or if it was a simple oversight, but `Box<T>` has
three pieces of behavior that could not be replicated in pure Rust at the time:

 - `box foo` in a pattern would destructure a box into its contents. It's somewhat the opposite of `ref`
 - `box foo()` performed placement box, so the result of `foo()` could be directly written to a preallocated box, reducing extraneous copies
 - You could _move out of deref_ with `Box<T>`

The third one is the one that really gets to us here[^4].
For a _regular_ type, `*foo` will produce a temporary that must be immediately borrowed or copied.
You cannot do `let x = *y` for a non-`Copy` type. This dereference operation will call
`DerefMut::deref_mut` or `Deref::deref` based on how it gets borrowed. With `Box<T>`, you can do
this:

```rust
let x = Box::new(vec![1,2,3,4]);
let y = *x; // moves the vec out into `y`, then deallocates the box
            // but does not call a destructor on the vec
```

For any other type, such an operation will produce a "cannot move out of a borrow" error.

This operation is colloquially called `DerefMove`, and there has been [an rfc][derefmove] in the
past for making it into a trait. I suspect that the `DerefMove` semantics could even have been
removed from `Box<T>` before 1.0 (I don't find it _necessary_), but people had better things to do,
like fixing the million other rough edges of the language that can't be touched after backwards
compatibility is a thing.


So now we're stuck with it. The current status is that `Box<T>` is _still_ a special type in the
compiler. By "special type" I don't just mean that the compiler treats it a bit differently (this is
true for any lang item), I mean that it literally is treated as
[a completely new kind of type][tybox], not as a struct the way it has been defined in liballoc.
There's a TON of cruft in the compiler related to this type, much of which can be removed, but some
of which can't. If we ever do get `DerefMove`, we should probably try removing it all again. After
writing this post I'm half-convinced to try and implement an internal-use-only `DerefMove` and try
cleaning up the code myself.


Most of this isn't really useful to know unless you actually come across a case where you can make
use of `DerefMove` semantics, or if you work on the compiler. But it certainly is interesting!

 [derefmove]: https://github.com/rust-lang/rfcs/pull/178/files?short_path=6f69a99#diff-6f69a990502a98c2eeb172d87269005d
 [tybox]: http://manishearth.github.io/rust-internals-docs/rustc/ty/enum.TypeVariants.html#TyBox.v
 [^4]: It's easier to special case the first two, much like how `for` loops are aware of the iterator trait without the iterator trait being extremely special cased
