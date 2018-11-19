---
layout: post
title: "Rust Tidbits: What is a lang item?"
date: 2017-01-11 21:01:13 -0800
comments: true
categories: rust mozilla programming tidbits
---


_Rust is not a simple language. As with any such language, it has many little tidbits of complexity
that most folks aren't aware of. Many of these tidbits are ones which may not practically matter
much for everyday Rust programming, but are interesting to know. Others may be more useful. I've
found that a lot of these aren't documented anywhere (not that they always should be), and sometimes
depend on knowledge of compiler internals or history. As a fan of programming trivia myself, I've
decided to try writing about these things whenever I come across them. "Tribal Knowledge" shouldn't
be a thing in a programming community; and trivia is fun!_

Previously in tidbits: [`Box` is Special][tidbit-box]

Last time I talked about `Box<T>` and how it is a special snowflake. Corey [asked][cmr-ask] that
I write more about lang items, which are basically all of the special snowflakes in the stdlib.


So what _is_ a lang item? Lang items are a way for the stdlib (and libcore) to define types, traits,
functions, and other items which the compiler needs to know about.

For example, when you write `x + y`, the compiler will effectively desugar that into
`Add::add(x, y)`[^1]. How did it know what trait to call? Did it just insert a call to
`::core::Add::add` and hope the trait was defined there? This is what C++ does;
the Itanium ABI spec expects functions of certain names
to just _exist_, which the compiler is supposed to call in various cases. The
`__cxa_guard_*` functions from C++s deferred-initialization local statics (which
I've [explored in the past][local-static]) are an example of this. You'll find that the spec is
full of similar `__cxa` functions. While the spec just expects certain types,
e.g. `std::type_traits` ("Type properties" § 20.10.4.3), to be magic and exist in certain locations,
the compilers seem to implement them using intrinsics like `__is_trivial<T>` which aren't defined
in C++ code at all. So C++ compilers have a mix of solutions here, they partly insert calls
to known ABI functions, and they partly implement "special" types via intrinsics which
are detected and magicked when the compiler comes across them.


However, this is not Rust's solution. It does not care what the `Add` trait is named or where it is
placed. Instead, it knew where the trait for addition was located because [_we told it_][add-lang].
When you put `#[lang = "add"]` on a trait, the compiler knows to call `YourTrait::add(x, y)` when it
encounters the addition operator. Of course, usually the compiler will already have been told about
such a trait since libcore is usually the first library in the pipeline. If you want to actually use
this, you need to _replace libcore_.

Huh? You can't do that, can you?


 [tidbit-box]: http://manishearth.github.io/blog/2017/01/10/rust-tidbits-box-is-special/
 [cmr-ask]: https://www.reddit.com/r/rust/comments/5nb86x/rust_tidbits_box_is_special/dca4y6n/?utm_content=permalink&utm_medium=front&utm_source=reddit&utm_name=rust
 [add-lang]: https://github.com/rust-lang/rust/blob/2782e8f8fcefdce77c5e0dd0846c15c4c5103d84/src/libcore/ops.rs#L243
 [book-no-std]: https://doc.rust-lang.org/book/no-stdlib.html
 [local-static]: http://manishearth.github.io/blog/2015/06/26/adventures-in-systems-programming-c-plus-plus-local-statics/
 [^1]: Though as we learned in the previous post, when `x` and `y` are known numeric types it will bypass the trait and directly generate an add instruction in LLVM


It's not a big secret that you can compile rust without the stdlib using
[`#![no_std]`][book-no-std]. This is useful in cases when you are on an embedded system and can't
rely on an allocator existing. It's also useful for writing your own alternate stdlib, though
that's not something folks do often. Of course, libstd itself [uses `#![no_std]`][libstd-nostd],
because without it the compiler will happily inject an `extern crate std` while trying to compile
libstd and the universe will implode.


What's less known is that you can do the same thing with libcore, via `#![no_core]`. And, of course,
libcore [uses it][libcore-nocore] to avoid the cyclic dependency. Unlike `#![no_std]`, `no_core` is
a nightly-only feature that we may never stabilize[^2]. `#![no_core]` is something that's basically
only to be used if you _are_ libcore (or you are an alternate Rust stdlib/core implementation
trying to emulate it).

 [^2]: To be clear, I'm not aware of any plans to eventually stabilize this. It's something that could happen.

Still, it's possible to write a working Rust binary in `no_core` mode:


```rust
#![feature(no_core)]
#![feature(lang_items)]

// Look at me.
// Look at me.
// I'm the libcore now.
#![no_core]

// Tell the compiler to link to appropriate runtime libs
// (This way I don't have to specify `-l` flags explicitly)
#[cfg(target_os = "linux")]
#[link(name = "c")]
extern {}
#[cfg(target_os = "macos")]
#[link(name = "System")]
extern {}

// Compiler needs these to proceed
#[lang = "sized"]
pub trait Sized {}
#[lang = "copy"]
pub trait Copy {}

// `main` isn't the actual entry point, `start` is.
#[lang = "start"]
fn start(_main: *const u8, _argc: isize, _argv: *const *const u8) -> isize {
    // we can't really do much in this benighted hellhole of
    // an environment without bringing in more libraries.
    // We can make syscalls, segfault, and set the exit code.
    // To be sure that this actually ran, let's set the exit code.
    42
}

// still need a main unless we want to use `#![no_main]`
// won't actually get called; `start()` is supposed to call it
fn main() {}
```

If you run this, the program will exit with exit code 42.

Note that this already adds two lang items. `Sized` and `Copy`. It's usually worth
[looking at the lang item in libcore][sized-source] and copying it over unless you want to make
tweaks. Beware that tweaks may not always work; not only does the compiler expect the lang item
to exist, it expects it to make sense. There are properties of the lang item that it assumes
are true, and failure to provide an appropriate lang item may cause the compiler to assert
without a useful error message. In this case I do have a tweak, since
the original definition of `Copy` is `pub trait Copy: Clone {}`, but I know that this tweak
will work.

Lang items are usually only required when you do an operation which needs them. There are 72 non-
deprecated lang items and we only had to define three of them here. "start" is necessary to, well,
start executables, and `Copy`/`Sized` are very crucial to how the compiler reasons about types and
must exist.

But let's try doing something that will trigger a lang item to be required:

```rust
pub static X: u8 = 1;
```

Rust will immediately complain:

```
$ rustc test.rs
error: requires `sync` lang_item
```

This is because Rust wants to enforce that types in statics (which can be accessed concurrently)
are safe when accessed concurrently, i.e., they implement `Sync`. We haven't defined `Sync` yet,
so Rust doesn't know how to enforce this restruction. The `Sync` trait is defined with the "sync"
lang item, so we need to do:

```rust
pub static X: u8 = 1;

#[lang = "sync"]
pub unsafe trait Sync {}
unsafe impl Sync for u8 {}
```

Note that the trait doesn't have to be called `Sync` here, any trait name would work. This
definition is also a slight [departure from the one in the stdlib][sync-source], and in general you
should include the auto trait impl (instead of specifically using `unsafe impl Sync for u8 {}`)
since the compiler may assume it exists. Our code is small enough for this to not matter.



 [libstd-nostd]: https://github.com/rust-lang/rust/blob/2782e8f8fcefdce77c5e0dd0846c15c4c5103d84/src/libstd/lib.rs#L213-L214
 [libcore-nocore]: https://github.com/rust-lang/rust/blob/2782e8f8fcefdce77c5e0dd0846c15c4c5103d84/src/libcore/lib.rs#L65
 [sized-source]: https://github.com/rust-lang/rust/blob/2782e8f8fcefdce77c5e0dd0846c15c4c5103d84/src/libcore/marker.rs#L88-L94
 [sync-source]: https://github.com/rust-lang/rust/blob/2782e8f8fcefdce77c5e0dd0846c15c4c5103d84/src/libcore/marker.rs#L343-L351


Alright, let's try defining our own addition trait as before. First, let's see
what happens if we try to add a struct when addition isn't defined:

```rust
struct Foo;
#[lang = "start"]
fn start(_main: *const u8, _argc: isize, _argv: *const *const u8) -> isize {
    Foo + Foo
}
```

We get an error:

```
$ rustc test.rs
error[E0369]: binary operation `+` cannot be applied to type `Foo`
  --> test.rs:33:5
   |
33 |     Foo + Foo
   |     ^^^
   |
note: an implementation of `std::ops::Add` might be missing for `Foo`
  --> test.rs:33:5
   |
33 |     Foo + Foo
   |     ^^^

error: aborting due to previous error
```

It is interesting to note that here the compiler _did_ refer to `Add` by its path.
This is because the diagnostics in the compiler are free to assume that libcore
exists. However, the actual error just noted that it doesn't know how to add two
`Foo`s. But we can tell it how!


```rust
#[lang = "add"]
trait MyAdd<RHS> {
    type Output;
    fn add(self, other: RHS) -> Self::Output;
}

impl MyAdd<Foo> for Foo {
    type Output = isize;
    fn add(self, other: Foo) -> isize {
        return 42;
    }
}

struct Foo;
#[lang = "start"]
fn start(_main: *const u8, _argc: isize, _argv: *const *const u8) -> isize {
    Foo + Foo
}
```

This will compile fine and the exit code of the program will be 42.

An interesting bit of behavior is what happens if we try to add two numbers. It will give us the
same kind of error, even though the addition of concrete primitives doesn't
go through `Add::add` (Rust asks LLVM to generate an add instruction directly). However, any addition operation still checks if `Add::add` is implemented, even though it won't get _used_ in the case of a primitive. We can even verify this!

```rust
#[lang = "add"]
trait MyAdd<RHS> {
    type Output;
    fn add(self, other: RHS) -> Self::Output;
}

impl MyAdd<isize> for isize {
    type Output = isize;
    fn add(self, other: isize) -> isize {
        self + other + 50
    }
}

struct Foo;
#[lang = "start"]
fn start(_main: *const u8, _argc: isize, _argv: *const *const u8) -> isize {
    40 + 2
}
```

This will need to be compiled with `-C opt-level=2`, since numeric addition in debug mode panics on
wrap and we haven't defined the `"panic"` lang item to teach the compiler _how_ to panic.

It will exit with 42, not 92, since while the `Add` implementation is required for this to type
check, it doesn't actually get used.


----------

So what lang items _are_ there, and why are they lang items? There's a [big list][lang-list] in the
compiler. Let's go through them:

The [`ImplItem` ones][lang-impl-item] ([core][impl-char]) are used to mark implementations on
primitive types. `char` has some methods, and _someone_ has to say `impl char` to define them. But
coherence only allows us to impl methods on types defined in our own crate, and `char` isn't defined
... in any crate, so how do we add methods to it? `#[lang = "char"]` provides an escape hatch;
applying that to `impl char` will allow you to break the coherence rules and add methods,
[as is done in the standard library][impl-char]. Since lang items can only be defined once, only
a single crate gets the honor of adding methods to `char`, so we don't have any of the issues that
arise from sidestepping coherence.

There are a bunch for the [marker traits][lang-marker] ([core][lang-marker-impl]):

 - `Send` is a lang item because you are allowed to use it in a `+` bound in a trait object (`Box<SomeTrait+Send+Sync>`), and the compiler caches it aggressively
 - `Sync` is a lang item for the same reasons as `Send`, but also because the compiler needs to enforce its implementation on types used in statics
 - `Copy` is fundamental to classifying values and reasoning about moves/etc, so it needs to be a lang item
 - `Sized` is also fundamental to reasoning about which values may exist on the stack. It is also magically included as a bound on generic parameters unless excluded with `?Sized`
 - [`Unsize`][unsize] is implemented automatically on types using a specific set of rules ([listed in the nomicon][nom-unsize]). Unlike `Send` and `Sync`, this mechanism for autoimplementation is tailored for the use case of `Unsize` and can't be reused on user-defined marker traits.

[`Drop` is a lang item][lang-drop] ([core][lang-drop-impl]) because the compiler needs to know which types have destructors, and how to call
these destructors.

[`CoerceUnsized`][CoerceUnsized] [is a lang item][lang-coerceunsized]
([core][lang-coerceunsized-impl]) because the compiler is allowed to perform
[DST coercions][dst-coerce] ([nomicon][nom-unsize]) when it is implemented.

[All of the builtin operators][lang-builtin] (also [`Deref`][lang-deref]
and [`PartialEq`/`PartialOrd`][lang-eq], which are listed later in the file) ([core][lang-builtin-impl])
are lang items because the compiler needs to know what trait to require (and call)
when it comes across such an operation.

[`UnsafeCell`][UnsafeCell] [is a lang item][lang-unsafecell]
([core][lang-unsafecell-impl]) because it has very special semantics; it prevents
certain optimizations. Specifically, Rust is allowed to reorder reads/writes to `&mut foo` with the
assumption that the local variable holding the reference is the only alias allowed to read from
or write to the data, and it is allowed to reorder reads from `&foo` assuming that no other alias
writes to it. We tell LLVM that these types are `noalias`. `UnsafeCell<T>` turns this optimization
off, allowing writes to `&UnsafeCell<T>` references. This is used in the implementation of interior
mutability types like `Cell<T>`, `RefCell<T>`, and `Mutex<T>`.

The [`Fn` traits][lang-fn] ([core][lang-fn-impl]) are used in dispatching function calls,
and can be specified with special syntax sugar, so they need to be lang items. They also
get autoimplemented on closures.

[The `"str_eq"` lang item][lang-streq] is outdated. It *used* to specify how to check the equality
of a string value against a literal string pattern in a `match` (`match` uses structural equality,
not `PartialEq::eq`), however I believe this behavior is now hardcoded in the compiler.

[The panic-related lang items][lang-panic] ([core][lang-panic-impl]) exist because rustc itself
inserts panics in a few places. The first one, `"panic"`, is used for integer overflow panics in debug mode, and
`"panic_bounds_check"` is used for out of bounds indexing panics on slices. The last one,
`"panic_fmt"` hooks into a function defined later in libstd.

The [`"exchange_malloc"` and `"box_free"`][lang-boxalloc] ([alloc][lang-boxalloc-impl]) are for
telling the compiler which functions to call in case it needs to do a `malloc()` or `free()`. These
are used when constructing `Box<T>` via placement `box` syntax and when moving out of a deref of a
box.

[`"strdup_uniq"`][lang-strdup] seemed to be used in the past for moving string literals to the heap,
but is no longer used.

We've already seen [the start lang item][lang-start] ([std][lang-start-impl]) being used in our
minimal example program. This function is basically where you find Rust's "runtime": it gets called
with a pointer to main and the command line arguments, it sets up the "runtime", calls main, and
tears down anything it needs to. Rust has a C-like minimal runtime, so
[the actual libstd definition][lang-start-impl] doesn't do much.
But you theoretically could stick a very heavy runtime initialization routine here.

The [exception handling lang items][lang-eh] ([panic_unwind][lang-eh-impl], in multiple
platform-specific modules) specify various bits of the exception handling behavior. These hooks are
called during various steps of unwinding: `eh_personality` is called when determining whether
or not to stop at a stack frame or unwind up to the next one. `eh_unwind_resume` is the routine
called when the unwinding code wishes to resume unwinding after calling destructors in a landing
pad. `msvc_try_filter` defines some parameter that MSVC needs in its unwinding code. I don't
understand it, and apparently, [neither does the person who wrote it][lulz].


The [`"owned_box"`][lang-box] ([alloc][lang-box-impl]) lang item tells the compiler which type is
the `Box` type. In my previous post I covered how `Box` is special; this lang item is how the
compiler finds impls on `Box` and knows what the type is. Unlike the other primitives, `Box` doesn't
actually have a type name (like `bool`) that can be used if you're writing libcore or libstd. This
lang item gives `Box` a type name that can be used to refer to it. (It also defines some,
but not all, of the semantics of `Box<T>`)

The [`"phantom_data"`][lang-phantom] ([core][lang-phantom-impl]) type itself is allowed to have
an unused type parameter, and it can be used to help fix the variance and drop behavior
of a generic type. More on this in [the nomicon][nom-phantom].

The [`"non_zero"`][lang-nonzero] lang item ([core][lang-nonzero-impl]) marks the `NonZero<T>` type,
a type which is guaranteed to never contain a bit pattern of only zeroes. This is used inside things
like `Rc<T>` and `Box<T>` -- we know that the pointers in these can/should never be null, so they
contain a `NonZero<*const T>`. When used inside an enum like `Option<Rc<T>>`, the discriminant
(the "tag" value that distinguishes between `Some` and `None`) is no longer necessary, since
we can mark the `None` case as the case where the bits occupied by `NonZero` in the `Some` case
are zero. Beware, this optimization also applies to C-like enums that don't have a variant
corresponding to a discriminant value of zero (unless they are `#[repr(C)]`)

There are also a bunch of deprecated lang items there. For example, `NoCopy` used to be a struct
that could be dropped within a type to make it not implement `Copy`; in the past `Copy`
implementations were automatic like `Send` and `Sync` are today. `NoCopy` was the way to opt out.
There also used to be `NoSend` and `NoSync`. `CovariantType`/`CovariantLifetime`/etc were the
predecessors of `PhantomData`; they could be used to specify variance relations of a type with its
type or lifetime parameters, but you can now do this with providing the right `PhantomData`, e.g.
`InvariantType<T>` is now `PhantomData<Cell<T>>`.
The [nomicon][nom-variance] has more on variance. I don't know why these lang items haven't been
removed (they don't work anymore anyway); the only consumer of them is libcore so "deprecating" them
seems unnecessary. It's probably an oversight.

Interestingly, `Iterator` and `IntoIterator` are _not_ lang items, even though they are used in `for`
loops. Instead, the compiler inserts hardcoded calls to `::std::iter::IntoIterator::into_iter` and
`::std::iter::Iterator::next`, and a hardcoded reference to `::std::option::Option` (The paths use
`core` in `no_std` mode). This is probably because the compiler desugars `for` loops before type
resolution is done, so withut this, libcore would not be able to use for loops since the compiler
wouldn't know what calls to insert in place of the loops while compiling.


 [lang-list]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/librustc/middle/lang_items.rs#L252-L363
 [lang-impl-item]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/librustc/middle/lang_items.rs#L254-L272
 [impl-char]: https://github.com/rust-lang/rust/blob/2782e8f8fcefdce77c5e0dd0846c15c4c5103d84/src/libstd_unicode/char.rs#L134-L135
 [lang-marker]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/librustc/middle/lang_items.rs#L274-L278
 [lang-marker-impl]: https://github.com/rust-lang/rust/blob/408c2f7827be838aadcd05bd041dab94388af35d/src/libcore/marker.rs#L41-L356
 [nom-unsize]: https://doc.rust-lang.org/nomicon/coercions.html
 [unsize]: https://doc.rust-lang.org/nightly/std/marker/trait.Unsize.html
 [lang-drop]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/librustc/middle/lang_items.rs#L280
 [lang-drop-impl]: https://github.com/rust-lang/rust/blob/408c2f7827be838aadcd05bd041dab94388af35d/src/libcore/ops.rs#L174-L197
 [lang-coerceunsized]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/librustc/middle/lang_items.rs#L282
 [lang-coerceunsized-impl]: https://github.com/rust-lang/rust/blob/408c2f7827be838aadcd05bd041dab94388af35d/src/libcore/ops.rs#L2743-L2746
 [CoerceUnsized]: https://doc.rust-lang.org/nightly/std/ops/trait.CoerceUnsized.html
 [dst-coerce]: https://github.com/rust-lang/rfcs/blob/master/text/0982-dst-coercion.md
 [lang-builtin]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/librustc/middle/lang_items.rs#L284-L307
 [lang-builtin-impl]: https://github.com/rust-lang/rust/blob/408c2f7827be838aadcd05bd041dab94388af35d/src/libcore/ops.rs#L243-L2035
 [UnsafeCell]: http://doc.rust-lang.org/std/cell/struct.UnsafeCell.html
 [lang-unsafecell]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/librustc/middle/lang_items.rs#L309
 [lang-unsafecell-impl]: https://github.com/rust-lang/rust/blob/408c2f7827be838aadcd05bd041dab94388af35d/src/libcore/cell.rs#L1065-L1069
 [lang-deref]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/librustc/middle/lang_items.rs#L311-L312
 [lang-eq]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/librustc/middle/lang_items.rs#L318-L319
 [lang-fn]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/librustc/middle/lang_items.rs#L314-L316
 [lang-fn-impl]: https://github.com/rust-lang/rust/blob/408c2f7827be838aadcd05bd041dab94388af35d/src/libcore/ops.rs#L2556-L2659
 [lang-streq]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/librustc/middle/lang_items.rs#L321
 [lang-panic]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/librustc/middle/lang_items.rs#L332-L334
 [lang-panic-impl]: https://github.com/rust-lang/rust/blob/408c2f7827be838aadcd05bd041dab94388af35d/src/libcore/panicking.rs#L39-L58
 [lang-boxalloc]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/librustc/middle/lang_items.rs#L336-L337
 [lang-boxalloc-impl]: https://github.com/rust-lang/rust/blob/408c2f7827be838aadcd05bd041dab94388af35d/src/liballoc/heap.rs#L129-L152
 [lang-strdup]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/librustc/middle/lang_items.rs#L338
 [lang-start]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/librustc/middle/lang_items.rs#L340
 [lang-start-impl]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/libstd/rt.rs#L31-L67
 [lang-eh]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/librustc/middle/lang_items.rs#L342-L344
 [lang-eh-impl]: https://github.com/rust-lang/rust/blob/408c2f7827be838aadcd05bd041dab94388af35d/src/libpanic_unwind/seh.rs
 [lulz]: https://github.com/rust-lang/rust/blob/408c2f7827be838aadcd05bd041dab94388af35d/src/libpanic_unwind/seh.rs#L232
 [lang-box]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/librustc/middle/lang_items.rs#L346
 [lang-box-impl]: https://github.com/rust-lang/rust/blob/408c2f7827be838aadcd05bd041dab94388af35d/src/liballoc/boxed.rs#L105-L107
 [lang-phantom]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/librustc/middle/lang_items.rs#L348
 [lang-phantom-impl]: https://github.com/rust-lang/rust/blob/2782e8f8fcefdce77c5e0dd0846c15c4c5103d84/src/libcore/marker.rs#L544-L546
 [nom-phantom]: https://doc.rust-lang.org/nomicon/phantom-data.html
 [lang-nonzero]: https://github.com/rust-lang/rust/blob/1ca100d0428985f916eea153886762bed3909771/src/librustc/middle/lang_items.rs#L360
 [lang-nonzero-impl]: https://github.com/rust-lang/rust/blob/2782e8f8fcefdce77c5e0dd0846c15c4c5103d84/src/libcore/nonzero.rs#L38-L42
 [nom-variance]: https://doc.rust-lang.org/nomicon/subtyping.html


------------


Basically, whenever the compiler needs to use special treatment with an item -- whether it be
dispatching calls to functions and trait methods in various situations, conferring special semantics
to types/traits, or requiring traits to be implemented, the type will be defined in the standard
library (libstd, libcore, or one of the crates behind the libstd façade), and marked as a lang item.

Some of the lang items are useful/necessary when working without libstd. Most only come into play if
you want to replace libcore, which is a pretty niche thing to do, and knowing about them is rarely
useful outside of the realm of compiler hacking.

But, like with the `Box<T>` madness, I still find this quite interesting, even if it isn't generally
useful!
