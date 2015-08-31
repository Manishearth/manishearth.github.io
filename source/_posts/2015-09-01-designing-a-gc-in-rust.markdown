---
layout: post
title: "Designing a GC in Rust"
date: 2015-09-01 00:23:40 +0530
comments: true
categories: programming rust mozilla
---


For a while I've been working on a [garbage collector for Rust][gc] with [Michael
Layzell][mystor]. I thought this would be a good time to talk of our design and progress so far.


 [gc]: http://github.com/Manishearth/rust-gc/
 [mystor]: http://github.com/mystor

# Motivation

"Wait", you ask, "why does Rust need a garbage collector"? Rust is supposed to work _without_ a GC,
that's one of its main selling points!

True. Rust _does_ work pretty well without a GC. It's managed to do without one so far, and we still
have all sorts of well-written crates out there (none of which use a GC).

But Rust is not just about low-cost memory safety. It's also [about choosing your costs and
guarantees][wrap]. `Box<T>` and stack allocation are not always sufficient, sometimes one needs to
reach for something like `Rc<T>` (reference counting). But even `Rc` is not perfect; it can't handle
cycles between pointers. There are solutions to that issue like using `Weak<T>`, but that only works
in limited cases (when you know what the points-to graph looks like at compile time), and isn't very
ergonomic.

Cases where one needs to maintain a complicated, dynamic graph are where a GC becomes useful.
Similarly, if one is writing an interpreter for a GCd language, having a GC in Rust would simplify
things a lot.

Not to say that one should pervasively use a GC in Rust. Similar to `Rc<T>`, it's best to use
regular ownership-based memory management as much as possible, and sprinkle `Rc`/`Gc` in places
where your code needs it.

 [wrap]: http://manishearth.github.io/blog/2015/05/27/wrapper-types-in-rust-choosing-your-guarantees/

# Previous designs

This isn't the first GC in Rust. Automatic memory management has existed before in various forms,
but all were limited.

Besides the ones listed below, Nick Fitzgerald's [cycle collector][cc] based on [this paper][r-b]
exists and is something that you should look into if you're interested. There's also [an RFC][mo-gc]
by Peter Liniker which sketches out a design for an immutable GC.


 [cc]: https://github.com/fitzgen/bacon-rajan-cc
 [r-b]: researcher.watson.ibm.com/researcher/files/us-bacon/Bacon01Concurrent.pdf
 [mo-gc]: https://github.com/pliniker/mo-gc/blob/master/doc/Project-RFC.md

## Core Rust GC(s)

Rust itself had a garbage collector until a bit more than a year ago. These "managed pointers"
(`@T`) were part of the language. They were removed later with a plan to make GC a library feature.

I believe these were basically reference counted (cycle collected?) pointers with some language
integration, but I'm not sure.

Nowadays, the only form of automatic memory management in Rust are via [`Rc`][rc] and [`Arc`][arc]
which are nonatomic and atomic reference counted pointers respectively. In other words, they keep
track of the number of shared references via a reference count (incremented when it is cloned,
decremented when destructors run). If the reference count reaches zero, the contents are cleaned up.

This is a pretty useful abstraction, however, as mentioned above, it doesn't let you create cycles
without leaking them.

 [rc]: http://doc.rust-lang.org/alloc/rc/struct.Rc.html
 [arc]: http://doc.rust-lang.org/std/sync/struct.Arc.html

## Spidermonkey

_You can read more about Servo's Spidermonkey bindings [in this blog post][sm-blog] (somewhat
outdated, but still relevant)_

In Servo we use [bindings to the Spidermonkey Javascript engine][r-mozjs]. Since Javascript is a
garbage collected language, the Rust representations of Javascript objects are also garbage
collected.

Of course, this sort of GC isn't really useful for generic use since it comes bundled with a JS
runtime. However, the Rust side of the GC is of a design that could be used in an independent
library.

The Rust side of the Spidermonkey GC is done through a bunch of smart pointers, and a trait called
`JSTraceable`. `JSTraceable` is a trait which can "trace" recursively down some data, finding and
marking all GC-managed objects inside it. This is autoderived using Rust's plugin infrastructure, so
a simple `#[jstraceable]` annotation will generate trace hooks for the struct it is on.

Now, we have various smart pointers. The first is `JS<T>`. This is opaque, but can be held by other
GC-managed structs. To use this on the stack, this must be explicitly _rooted_, via `.root()`. This
produces a `Root<T>`, which can be dereferenced to get the inner object. When the `Root` is created,
the contained object is listed in a collection of "roots" in a global. A root indicates that the
value is being used on the stack somewhere, and the GC starts tracing usage from these roots. When
the `Root<T>` is destroyed, the root is removed.

The problem with this is that `JS<T>` doesn't work on the stack. There is no way for the GC to know
that we are holding on to `JS<T>` on the stack. So, if I copy a `JS<T>` to the stack, remove all
references to it from objects in the GC heap, and trigger a collection, the `JS<T>` will still be
around on the stack after collection since the GC can't trace to it. If I attempt to root it, I may
get a panic or a segfault depending on the implementation.

To protect against this, we have a bunch of lints. The [relevant one][must_root] here protects
against `JS<T>` from being carried around on the stack; but like most lints, it's not perfect.

To summarize: Spidermonkey gives us a good GC. However using it for a generic Rust program is ill
advised. Additionally, Servo's wrappers around the GC are cheap, but need lints for safety. While it
would probably be possible to write safer wrappers for general usage, it's pretty impractical to
carry around a JS runtime when you don't need one.

However, Spidermonkey's GC did inspire me to think more into the matter.


 [r-mozjs]: http://github.com/servo/rust-mozjs/
 [must_root]: https://github.com/servo/servo/blob/master/components/plugins/lints/unrooted_must_root.rs
 [sm-blog]: https://blog.mozilla.org/research/2014/08/26/javascript-servos-only-garbage-collector/

# Brainstorming a design

For quite a while I'd had various ideas about GCs. Most were simplifications of Servo's wrappers
(there's some complexity brought in there by Spidermonkey that's not necessary for a general GC).
Most were tracing/rooting with mark-and-sweep collection. All of them used lints. Being rather busy,
I didn't really work on it past that, but planned to work on it if I could find someone to work
with.

One day, [Michael][mystor] pinged me on IRC and asked me about GCs. Lots of people knew that I was
interested in writing a GC for Rust, and one of them directed him to me when he expressed a similar
interest.

So we started discussing GCs. We settled on a tracing mark-and-sweep GC. In other words, the GC runs
regular "sweeps" where it first "traces" the usage of all objects and marks them and their children
as used, and then sweeps up all unused objects.

This model on its own has a flaw. It doesn't know about GC pointers held on the stack as local
variables ("stack roots"). There are multiple methods for solving this. We've already seen one above
in the Spidermonkey design -- maintain two types of pointers (one for the stack, one for the heap),
and try very hard using static analysis to ensure that they don't cross over.

A common model (used by GCs like Boehm, called "conservative GCs") is to do something called "stack
scanning". In such a system, the GC goes down the stack looking for things which may perhaps be GC
pointers. Generally the GC allocates objects in known regions of the memory, so a GC pointer is any
value on the stack which belongs to one of these regions.

Of course, this makes garbage collection rather inefficient, and will miss cases like `Box<Gc<T>>`
where the GCd pointer is accessible, but through a non-GC pointer.

We decided rather early on that we didn't want a GC based on lints or stack scanning. Both are
rather suboptimal solutions in my opinion, and very hard to make sound[^1]. We were also hoping that
Rust's type system and ownership semantics could help us in designing a good, safe, API.

 [^1]: I'm very skeptical that it's possible to make either of these completely sound without writing lints which effectively rewrite a large chunk of the compiler

So, we needed a way to keep track of roots, and we needed a way to trace objects.

## Tracing

The latter part was easy. We wrote a compiler plugin (well, we stole [Servo's tracing plugin which
I'd written earlier][jstraceable]) which autoderives an implementation of the `Trace` trait on any
given struct or enum, using the same internal infrastructure that `#[derive(PartialEq)]` and the
rest use. So, with just the following code, it's easy to make a struct or enum gc-friendly:


```rust
#[derive(Trace)]
struct Foo {
    x: u8,
    y: Bar,
}

#[derive(Trace)]
enum Bar {
    Baz(u8), Quux
}
```

For a `foo` of type `Foo` `foo.trace()`, will expand to a call of `foo.x.trace()` and
`foo.y.trace()`. `bar.trace()` will check which variant it is and call `trace()` on the `u8` inside
if it's a `Baz`. For most structs this turns out to be a no-op and is often optimized away by
inlining, but if a struct contains a `Gc<T>`, the special implementation of `Trace` for `Gc<T>` will
"mark" the traceability of the `Gc<T>`. Types without `Trace` implemented cannot be used in types
implementing `Trace` or in a `Gc`, which is enforced with a `T: Trace` bound on `Gc<T>`.

So, we have a way of walking the fields of a given object and finding inner `Gc<T>`s. Splendid. This
lets us write the mark&sweep phase easily: Take the list of known reachable `Gc<T>`s, walk their
contents until you find more `Gc<T>`s (marking all you find), and clean up any which aren't
reachable.


 [jstraceable]: https://github.com/servo/servo/blob/master/components/plugins/jstraceable.rs#L38

## Rooting 

Of course, now we have to solve the problem of keeping track of the known reachable `Gc<T>`s, i.e.
the roots. This is a hard problem to solve without language support, and I hope that eventually we
might be able to get the language hooks necessary to solve it. LLVM [has support for tracking
GCthings on the stack][llvm-stack], and some day we may be able to leverage that in Rust.

As noted above, Spidermonkey's solution was to have non-rooted (non-dereferencable) heap pointers,
which can be explicitly converted to rooted pointers and then read.

We went the other way. All `Gc<T>` pointers, when created, are considered "rooted". The instance of
`Gc<T>` has a "rooted" bit set to true, and the underlying shared box (`GcBox`, though this is not a
public interface) has its "root count" set to one.

When this `Gc<T>` is cloned, an identical `Gc<T>` (with rooted bit set to true) is returned, and the
underlying root count is incremented. Cloning a `Gc` does not perform a deep copy.

```rust
let a = Gc::new(20); // a.root = true, (*a.ptr).roots = 1, (*a.ptr).data = 20

// ptr points to the underlying box, which contains the data as well as
// GC metadata like the root count. `Gc::new()` will allocate this box

let b = a.clone(); // b.root = true, (*a.ptr).roots++, b.ptr = a.ptr
```

This is rather similar to how `Rc` works, however there is no `root` field, and the `roots` counter
is called a "reference counter".

For regular local sharing, it is recommended to just use a borrowed reference to the inner variable
(borrowing works fine with rust-gc!) since there is no cost to creating this reference.

When a GC thing is put inside another GC thing, the first thing no longer can remain a root. This is
handled by "unrooting" the first GC thing:

```rust
struct Foo {
    bar: u32,
    baz: Gc<u32>,
}

let a = Gc::new(20); // why anyone would want to GC an integer I'll never know
                     // but I'll stick with this example since it's simple

let b = Gc::new(Foo {bar: 1, baz: a});
// a.root = false, (*a.ptr).roots--
// b initialized similar to previous example

// `a` was moved into `b`, so now `a` cannot be accessed directly here
// other than through `b`, and `a` is no longer a root.
// To avoid moving a, passing `a.clone()` to `b` will work
```

Of course, we need a way to traverse the object passed to the `Gc<T>`, in this case `Foo`, and look
for any contained `Gc<T>`s to unroot. Sound familiar? This needs the same mechanism that `trace()`
needed! We add struct-walking `root()` and `unroot()` methods to the `Trace` trait which are auto-
derived exactly the same way, and continue. (We don't need `root()` right now, but we will need it
later on).

Now, during collection, we can just traverse the list of `GcBox`s and use the ones with a nonzero
root count as roots for our mark traversal.

So far, so good. We have a pretty sound design for a GC that works ... for immutable data.

 [llvm-stack]: http://llvm.org/docs/GarbageCollection.html#gcroot

### Mutability

Like `Rc<T>`, `Gc<T>` is by default immutable. Rust abhors aliasable mutability, [even in single
threaded contexts][mutable], and both these smart pointers allow aliasing.

Mutation poses a problem for our GC, beyond the regular problems of aliasable mutability: It's
possible to move rooted things into heap objects and vice versa:

```rust
let x = Gc::new(20);

let y = Gc::new(None);

*y = Some(x); // uh oh, x is still considered rooted!

// and the reverse!

let y = Gc::new(Some(Gc::new(20)));

let x = y.take(); // x was never rooted!
// `take()` moves the `Some(Gc<u32>)` out of `y`, replaces it with `None`       
```

Since `Gc<T>` doesn't implement `DerefMut`, none of this is possible &mdash; one cannot mutate the
inner data. This is one of the places where Rust's ownership/mutability system works out awesomely
in our favor.

Of course, an immutable GC isn't very useful. We can't even create cycles in an immutable GC, so why
would anyone need this in the first place[^3]?

So of course, we needed to make it somehow mutable. People using `Rc<T>` solve this problem by using
`RefCell<T>`, which maintains something similar to the borrow semantics at runtime and is internally
mutable. `RefCell<T>` itself can't be used by us since it doesn't guard against the problem
illustrated above (and hence won't implement `Trace`, but a similar cell type would work).

So we created `GcCell<T>`. This behaves just like `RefCell<T>`, except that it will `root()` before
beginning a mutable borrow, and `unroot()` before ending it (well, only if it itself is not rooted,
which is tracked by an internal field similar to `Gc<T>`). Now, everything is safe:

```rust
#[derive(Trace)]
struct Foo {
    a: u8,
    b: GcCell<Gc<u8>>,
}

let x = Gc::new(20);

let y = Gc::new(Foo {a: 10, b: Gc::new(30)});
{
    *y.b.borrow_mut() = x; // the `Gc(30)` from `y.b` was rooted by this call
                           // but since we don't actually use it here,
                           // the destructor gets rid of it.
                           // We could use swap() to retain access to it.
    // ...
    // x unrooted
}


// and the reverse case works too:

let y = Gc::new(GcCell::new(Some(Gc::new(20))));

let x = y.borrow_mut().take(); // the inner `Some(Gc(20))` gets rooted by `borrow_mut()`
                               // before `x` can access it
```

So now, mutation works too! We have a working garbage collector!


 [^3]: There is a case to be made for an immutable GC which allows some form of deferred initialization of GC fields, however.
 [mutable]: http://manishearth.github.io/blog/2015/05/17/the-problem-with-shared-mutability/

# Open problems

## Destructors

I believe this can be solved without lints, but it _may_ require some upcoming features of Rust to
be implemented first (like specialization).

In essence, destructors implemented on a value inside `Gc<T>` can be unsafe. This will only happen
if they try to access values within a `Gc<T>` &mdash; if they do, they may come across a box that
has already been collected, or they may lengthen the lifetime of a box scheduled to be collected.

The basic solution to this is to use "finalizers" instead of destructors. Finalizers, like in Java,
are not guaranteed to run. However, we may need further drop hooks or trait specialization to make
an airtight interface for this. I don't have a concrete design for this yet, though.

## Concurrency

Our model mostly just works in a concurrent situation (with thread safety tweaks, of course); in
fact it's possible to make it so that the concurrent GC will not "stop the world" unless someone
tries to do a write to a `GcCell`. We have an experimental concurrent GC in [this pull
request][cgc]. We still need to figure out how to make interop between both GCs safe, though we may
just end up making them such that an object using one GC cannot be fed to an object using the other.

## Performance

So far we haven't really focused on performance, and worked on ensuring safety. Our collection
triggering algorithm, for example, was horribly inefficient, though we planned on improving it. The
wonderful Huon [fixed this][huon-pr], though.

Similarly, we haven't yet optimized storage. We have some ideas which we may work on later. (If you
want to help, contributions welcome!)

## Cross-crate deriving

Currently, an object deriving `Trace` should have `Trace`able children. This isn't always possible
when members from another crate (which does not depend on rust-gc) are involved. At the moment, we
allow an `#[unsafe_ignore_trace]` annotation on fields which are of this type (which excludes it
from being traced -- if that crate doesn't transitively depend on rust-gc, its members cannot
contain GCthings anyway unless generics are involved). It should be possible to detect whether or
not this is safe, and/or autoderive `Trace` using the opt-in builtin traits framework (needs
specialization to work), but at the moment we don't do anything other than expose that annotation.

Stdlib support for a global `Trace` trait that everyone derives would be awesome.

 [huon-pr]: https://github.com/Manishearth/rust-gc/pull/9
 [cgc]:  https://github.com/Manishearth/rust-gc/pull/6

# Conclusion

Designing a GC was a wonderful experience! I didn't get to write much code (I was busy and Michael
was able to implement most of it overnight because he's totally awesome), but the long design
discussions followed by trying to figure out holes in the GC design in every idle moment of the day
were quite enjoyable. GCs are very hard to get right, but it's very satisfying when you come up with
a design that works! I'm also quite happy at how well Rust helped in making a safe interface.

I encourage everyone to try it out and/or find holes in our design. Contributions of all kind
welcome, we'd especially love performance improvements and testcases.
