---
layout: post
title: "GC support in Rust: API design"
date: 2016-08-18 21:57:48 +0530
comments: true
categories: 
---

Recently we've been working on getting compiler-level GC support for Rust. The plan is to provide a
base set of APIs and intrinsics on which GCs can be built, without including an actual GC itself.
This blog post serves as status update and a pre-pre-rfc on the designs. I'm also going to walk
through the process of coming up with the current design. We'll soon be posting more detailed
design docs and discussion about some of the unresolved bits.

The motivation behind this is the same as [my motivation for writing rust-gc][motivation]. Firstly,
it makes it possible to integrate with languages which themselves have a GC. Being able to safely
pass around GCd types in Rust is very useful when writing libraries for Node, Python, or Ruby in
Rust.

Secondly, some algorithms are much neater when a GC is involved. Things like persistent
datastructures, for example, are easier to deal with when a GC is involved.
[There are ways around this requirement][crossbeam], but it's nice to have the full range of
options.

Rust tries to be safe without a GC, and this doesn't change that &mdash; we envision that GCs
in Rust will be rarely used except for some very specific use cases like the ones listed above.

Compiler support isn't strictly necessary for a GC in Rust to be safe. [rust-gc] manages to work
without compiler support (except for a `#[derive()]` plugin). However, there's a lot of manual
tracking of roots involved, which has a much higher cost than compiler-backed GCs. This is
suboptimal &mdash; we want GC support to be as efficient as possible.


[motivation]: http://manishearth.github.io/blog/2015/09/01/designing-a-gc-in-rust/
[crossbeam]: https://aturon.github.io/blog/2015/08/27/epoch/
[rust-gc]: https://github.com/Manishearth/rust-gc

## Design goals

We're considering GCs designed as a `Gc<T>` object, which, like [`Rc<T>`][rc], can be explicitly
wrapped around a value to move it to the GC heap. A pervasive GC (where every Rust object is GCd) is
an explicit non-goal; if you need a GC _everywhere_ a different language may make more sense. We're
expecting `Gc<T>` to be used only where needed, much like how `Rc<T>` is today.

We want this to work well with other Rust abstractions. Things like `Vec<Gc<T>>` should be
completely legal, for example.

We want implementors to have total freedom in how `Gc<T>` is represented -- _they_ define the type,
not the compiler. The compiler provides traits and intrinsics which can be used to find the GC
roots. It should be possible for implementors to provide safe APIs for `Gc<T>`. There will be no
canonical `Gc<T>` in the stdlib.

We are trying to support multiple GCs in a single binary. This should be a pretty niche thing to
need, but it strengthens the behavior of GCs as libraries (and not magical one-time things like
custom allocators). One possible use case for this is if a library internally uses a GC to run some
algorithm, and this library is used by an application which uses a GC for some other reason (perhaps
to talk to Node). Interacting GCs are hard to reason about, though. The current design leaves this
decision up to the GC designer &mdash; while it is possible to let your GCd object contain objects
managed by a different GC, this requires some explicit extra work. Interacting GCs is a _very_ niche
use case[^1], so if this ability isn't something we're adamant on supporting.

We also would like it to be safe to use trait objects with the GC. This raises some concerns which
I'll address in depth later in this post.



[rc]: https://doc.rust-lang.org/std/rc/struct.Rc.html
[^1]: Firefox does have a garbage collector and a cycle collector which interact, though, so it's not something which is unthinkable.


## Core design

The core idea is to use [LLVM stack maps][stackmap] to keep track of roots.

In a tracing GC, the concept of a "root" is basically something which can be directly reached
without going through other GC objects. In our case they will be cases of `Gc<T>` ending up on the
stack or in non-gc heap boxes which themselves are reachable from the stack. Some examples:

```rust
struct Foo {
    bar: Gc<Bar>,
}

struct Bar {
    inner: Gc<bool>,
}

// `bar` is a root
let bar = Gc::new(Bar::new());
// `bar.inner` is not a root, since it can't be
// accessed without going through `bar`

// `foo.bar` is a root:
let foo = Foo::new(); // This is a root


// `inner` is not a root, because it is a borrowed reference
let inner = &bar.inner;

// `rooted_bool` is a root, since it is a `Gc<bool>` on the stack
// (cloning has the same behavior as that on `Rc<T>`: it creates a
// new reference to the same value)
let rooted_bool = bar.inner.clone();

// `boxed_bar` is a root. While the Gc<Bar> is not on the stack,
// it can be reached without dereferencing another `Gc<T>`
// or passing through a borrowed reference
let boxed_bar = Box::new(Gc::new(Bar::new()));
```

When figuring out which objects are live ("tracing"), we need to have this initial set of "roots"
which contain the list of things directly reachable from the stack. From here, the GC can rifle
through the fields and subfields of the roots till it finds other GCd objects, which it can mark as
live and continue the process with.

Most runtimes for GCd languages have efficient ways of obtaining this list of roots. Contrast this
with conservative collectors like Boehm, which read in the whole stack and consider anything which
looks like a pointer to the GC heap to be a root. rust-gc's approach is inefficient too; because it
incurs an additional reference counting cost on copying and mutation.

However, the list of current roots is known at compile time; it's just a matter of which variables
are live at any point. We store this list of live variables in a per-call-site "stack map". To find
all the roots, you walk up the call stack, and for each call site look up its entry in the stack
map, which will contain the stack offsets of all the roots (and other metadata if we need it). LLVM
has native support for this. The stack map is stored in a separate section so there is no runtime
performance hit during regular execution, however some optimizations may be inhibited by turning on
GC.

So basically a GC will have access to a `walk_roots<F>(f: F) where F: FnMut(..)` intrinsic that will
yield all the roots to the provided function (which can then mark them as such and start tracing).

I'm not going to focus on the implementation of this intrinsic for this blog post &mdash; this might
be the subject of a later blog post by [Felix][pnkfelix] who is working on this.

Instead, I'm focusing on the higher-level API.

[pnkfelix]: http://github.com/pnkfelix/
[stackmap]: http://llvm.org/docs/StackMaps.html

## Identifying rootables

The first problem we come across with the design mentioned above is that the compiler doesn't yet
know how to distinguish between a root and a non-root. We can't mark _every_ variable as a root;
that would bloat the stack maps and make walking the roots a very expensive operation.

A very simple way of doing this is via a trait, `Root`.


```rust
// in libcore

unsafe trait Root {}

// auto-trait, anything containing
// a Root will itself be Root
unsafe impl !Root for .. {}

// references are never roots
unsafe impl<'a, T> !Root for &'a T {}


// in a gc impl

struct Gc<T> {
    // ..
}

unsafe impl<T> Root for Gc<T> {}
```

if we detect `Root` objects that are directly reachable, we consider them to be roots.

This has a flaw, it doesn't actually tell us how to find roots inside container types. What would we
do if there was a `Box<Gc<T>>` or a `Vec<Gc<T>>` on the stack? We can stick their entry in the stack
map, but the GC needs to know what to do with them!

We could store some type information in the map and let the GC hardcode how to root each container
type. This isn't extensible though; the GC will have to be able to handle types from arbitrary
crates too. Additionally, we have to solve this problem anyway for tracing &mdash; when tracing we
need to be able to find all values "contained" within a particular value, which is the same
operation we need to do to find roots.


For this purpose, we introduce the `Trace` trait:

```rust
// in libcore
unsafe trait Trace {
    fn trace(&self);
}

// in libcollections
// (or any third-party collections library)
unsafe impl<T: Trace> Trace for Vec<T> {
    fn trace(&self) {
        for i in self {
            i.trace()
        }
    }
}

// in gc library

// only allow trace objects
struct Gc<T: Trace> {
    // ..
}

unsafe impl<T> Trace for Gc<T> {
    fn trace(&self) {
        // mark `self`

        // Don't actually trace contained fields,
        // because there may be cycles and we'd recurse infinitely
    }
}

// in consumer of gc library

// autoderived impl will call `bar.trace()` and `baz.trace()`
#[derive(Trace)]
struct Foo {
    bar: Gc<Bar>,
    baz: SomeType,
}
```

(These traits are unsafe to implement because an incorrect implementation can lead to a
reachable value getting cleaned up by the GC, which is unsafe)

Basically, an implementation of Trace will yield all values owned by the object, unless that object
is a GC struct like `Gc<T>`, in which case the GC implementor will have it mark the object. This
way, calling `.trace()` will walk all fields and subfields of an object recursively, until it finds
all of the contained `Gc<T>`s.


This has an issue with multiple GCs, though &mdash; we don't want the GCs to interact unless they
want to, and with the `Trace` trait being shared one GC object may accidentally contain a different
GC object.

We need to introduce the concept of a tracer here.

```rust
// in libcore

trait Tracer : Any {}

unsafe trait Trace {
    fn trace(&self, tracer: &mut Tracer);
}


// in libcollections

// impl doesn't care about the tracer
unsafe impl<T: Trace> Trace for Vec<T> {
    fn trace(&self, tracer: &mut Tracer) {
        for i in self {
            i.trace(tracer)
        }
    }
}

// in gc library

struct MyTracer {} // more complicated tracers may have state
impl Tracer for MyTracer {}


struct Gc<T: Trace> {
    // ..
}

unsafe impl<T> Trace for Gc<T> {
    fn trace(&self, tracer: &mut Tracer) {
        if let Some(tracer) = tracer.downcast_mut::<MyTracer>() {
            // mark self
        } else {
            panic("Don't mix GCs!");
            // If you want to support multiple GCs interacting with each other,
            // you can let this else block trace the contents.
            // Beware, interacting GCs have subtle safety issues.
        }
    }
}
```


This also makes it easier to distinguish between rooting and tracing operations. While the
operations are similar ("to root/trace a value, walk its fields recursively till you find all of the
Gc<T>s, and root/mark *those*"), the code we run at the leaf `Gc<T>` nodes is different. In the
previous model, this could have been solved with a global static boolean that identifies if the code
is currently walking roots or tracing, but with the `Tracer` trait object we can just pass in
different tracer values.

We're not yet sure if we should be lumping root walking and tracing in a single trait; so we might
end up with a second `Scan` trait that works similarly.

Note that we're not getting rid of the Root trait here. This is because `Root` and `Trace` have
slightly incompatible purposes -- `Root` signals to the compiler if something definitely contains
roots, whereas `Trace` marks things which are safe to put inside a GC. `bool` is `Trace`, but not
`Root`. `Vec<Gc<T>>` is `Trace` and `Root`, `Vec<bool>` is `Trace` but not `Root`. `&T` and `&mut T`
are neither. `Trace` will actually show up in trait bounds for GC code. `Root` will only be analysed
by the compiler itself, bounds like `R: Root` probably won't show up.

There should not be any types which are `Root` but not `Trace`, because this means the compiler
won't know what to do with them!

Now, when generating the stack map, we include the stack offset of all `Root` objects in scope, as
well as appropriate dynamic dispatch vtable pointers for the `Trace` implementation[^3]. Walking the
stack involves calling the trace method on each entry in the stack map for each call site.

[^3]: If there is an active stack drop flag for the value, that will need to be included too.

## Unresolved problems

There are a lot of these. Suggestions very welcome.

### Trait objects

Trait objects provide an interesting challenge. They may or may not contain roots, but what's more
important is that trait objects in libraries that know nothing about GC may also contain roots.

For example, if a library is dealing with a `Box<SomeTrait>`, and your code feeds it a
`Box<SomeRoot as SomeTrait>`, the trait object is now a root. If a gc is triggered while in
this call (perhaps by a callback), then this trait object should be counted as a root.

But this library didn't depend on the GC, and when it was compiled, it wasn't compiled with stack
map entries for this GC object.

There are two solutions here. The first is to recompile everything (including libstd) from scratch
with GC support on, and put all owned trait objects in the stack maps. They will have an extra
generated trace entry in the vtable that will ignore the object if it isn't a root. To put trait
objects inside `Gc<T>`, you will have to explicitly use `Box<Trait+Trace>`, however -- this magical
trace entry is just for collecting roots.


The second solution is to simply not allow casting `Root` objects to owned trait objects. I feel
that there are use cases for both -- the former has extra bloat and requires a custom libstd (which
could be distributed via rustup if necessary), but the latter restricts how you use trait objects.
Servo, for example, would probably prefer the latter since we don't put our DOM objects in owned
trait objects. But other GC users may want maximum flexibility. Letting people choose this via a
codegen flag (which can be controlled via cargo) might be a good idea.

### Should it be `Trace<T>`?

There is a dynamic dispatch cost on rooting/tracing any `Gc<T>` leaf with the tracer model.

This can be obviated by having it be:

```rust
trait Trace<T: Tracer> {
    fn trace(&self, tracer: &mut T)
}
```

Most types would implement `Trace<T>`, and GCs can implement `Trace<SpecificTracer>`,
and only require their contents to be `Trace<SpecificTracer>`. This lets the type system
forbid interacting GCs instead of having it done at runtime.

This has multiple downsides, however:

 - `#[derive(Trace)]` becomes `#[derive(Trace<MyTracer>)]` for things containing `Gc<T>` (because `Gc<T>` is not `Trace<T>` for all `T`, and macro expansion runs before this information can be computed).
 - If there are multiple GCs, there are multiple `Trace<T>` vtable pointers in the stack map. Not all libs know about the other GC when being compiled, so you need to defer generation of these stack map entries somehow.
 - The heuristics for forbidding types which are `Root` but not `Trace<T>` become subtler. You have to effectively forbid types which are `Root` but do not have an impl of `Trace<T>` for at least one tracer `T` that is active in the compilation.

### Non-`Trace` collections on the stack

If something like the following, defined by a third-party library:

```rust
struct Foo<T> {
    x: T,
    // ...
}
```

doesn't implement `Trace`, it's still okay to use `Foo<RootedThing>` on the stack, because we can
figure out that the inner `T` is what we need to root.

However, if a third-party `MyVec<T>` (which behaves like a vector) contains `RootedThing`s, and is
on the stack, the compiler doesn't know what do do with it. Lack of a `Trace` bound makes it
impossible to put such types on the GC heap, but there's no restriction on putting these types on
the stack. As I mentioned before, we can simply forbid the existence of types which are `Root` but
not `Trace` (`MyVec<RootedThing>` is `Root`). This is already done with `Copy` and `Drop`.

There's a subtle difference between this and the `Copy`/`Drop` forbidding. `Copy` and `Drop` are
always explicitly implemented. On the other hand, `Root` is an auto trait and automatically
implements itself on types containing roots. This means that we can't necessarily forbid such types
being created at impl time &mdash; third party collections like above for example won't contain
`Root` types until they are monomorphised. We can error during monomorphization, but this error
might not be very user-friendly, like template errors in C++.

Another solution is to make `Root` into `?Root`, much like `?Sized`. This means that the writers of
collections will explicitly opt in to allowing GCd things inside them. This probably would lead to a
lot more churn, however. But the diagnostics would be clearer.

Turns out that
[this](https://play.rust-lang.org/?gist=ad485dc2fc91e5c1aad53051dc207716&version=nightly&backtrace=0)
actually works with half-decent diagnostics. This doesn't forbid the existence of types which impl
Root but not Trace, however. It simply avoids autoderiving Root on types which aren't Trace. But
this behavior can be changed.
(In fact, it [was changed][no-more-base-oibit] while this post was being written!)

It becomes more complicated with Trace<T> though.
Having `Root<T>` might fix this, but then you have to deal with the auto trait generics.

One solution for the auto trait generics is to simple not include `Root` in the stdlib. Instead,
require code like the following:

```rust
// in gc library

struct MyTracer {/* .. */}

struct Gc<T: Trace<MyTracer>> {
    // ...
}

#[gc_root_trait]
unsafe trait MyRoot: Trace<MyTracer> {}

unsafe impl !MyRoot for .. {}

unsafe impl<T: Trace<MyTracer>> MyRoot for Gc<T> {}
```

This can be further simplified by completely removing the rooting trait requirement and instead
require `#[gc(tracer=MyTracer)]` on all GC structs. This, however, is a bit more special and we lose
the free diagnostics that you get from utilizing the type system.

 [no-more-base-oibit]: https://github.com/rust-lang/rust/pull/35745

### Are `Root`-containing raw pointers `Root`?

For the auto-trait to work, types like `Vec<ContainsRoot>` should also be marked as `Root`.

This can be done by just marking `*const T` and `*mut T` as `Root` if `T` is `Root` using an impl in
libcore. However, borrowed types like `Iter` will also be dragged into this. We only want types
which _own_ `Root` things to be considered roots.

The alternative is to not require this, and solely rely on [`PhantomData`][phantom]. `Vec<T>` also
contains a `PhantomData<T>`, which gives the compiler a hint that it owns a `T`. On the other hand,
`Iter<'a, T>` contains a `PhantomData<&'a T>`, which hints that it borrows a `T`. This is already
used by the compiler to determine drop soundness, so we can just use the same thing to determine
`Root` types. This is already supported by the autotrait infrastructure.

A downside here is that we're relying more on producers of unsafe code remembering to use
`PhantomData`. I'm not 100% certain about this, but triggering dropck unsoundness by neglecting
`PhantomData` is still pretty hard (and often requires types like arenas), whereas forgetting a root
can very easily cause a GC segfault. I do not consider this to be a major downside.

[phantom]: https://doc.rust-lang.org/stable/nomicon/phantom-data.html

### Finalizers and Drop

The following code is unsafe:

```rust
struct Foo {
    bar: Gc<Bar>,
    baz: Gc<Baz> // baz can contain a Bar
}
impl Drop for Foo {
    fn drop(&mut self) {
        println!("{:?}", *bar);
        // or
        *self.baz.bar.borrow_mut() = bar.clone();
    }
}

// Foo itself is used as a `Gc<Foo>`
```

The problem is that destructors run in the sweep cycle of a GC, in some order. This means that `bar`
may have already been collected when `Foo`'s destructor runs. While in many cases this can be solved
with a smart collection alrogithm, in the case where there's a cycle being collected there's nowhere
safe to start.

Additionally, further mutation of the graph after collection may extend the lifetime of a to-be-
collected variable.

A simple solution is to forbid all GC accesses during the collection phase. However, this means
dereferences too, and this will incur a cost on all GCd types -- they stop being simple pointer
accesses. This solution places the burden on the GC implementor, instead of the compiler.

We have enough information in the type system to solve this -- we can forbid `Drop` impls on types
which are explicitly `Root`. But it turns out that this isn't enough. Consider:

```rust
trait MyTrait {
    fn do_the_thing(&self);
}
struct HijackableType<T: MyTrait> {
    x: T,
} 

impl<T> Drop for HijackableType<T> {
    fn drop(&mut self) {
        self.x.do_the_thing();
    }
}

// in other library

struct Bar {
    inner: Gc<Baz>
}

impl MyTrait for Bar {
    fn do_the_thing(&self) {
        println!("{:?}", *self.inner)
    }
}
```

`Foo<Bar>` now has an unsafe destructor. Stopping this behavior requres forbidding Drop impls on
structs with trait bounds, but that is too restrictive.

This may end up having a similar solution to the "all roots must be `Trace`" issue. Warning on
monomorphizations isn't enough, we need to be able to allow `Vec<ContainsRoot>`, but not
`HijackableType<ContainsRoot>`. Making this distinction without poisoning half the generics out
there is tricky.

The notion of a hijackable type is actually already important for sound generic drop impls, see
[RFC 1327 (dropck eyepatch)][rfc-eyepatch], [RFC 1238 (nonparametrick dropck)][rfc-nonparam],
and their predecessor, [RFC 0769 (sound generic drop)][rfc-sound]. We might be able to rely
on this, but would need to introduce additional constraints in dropck.

Fortunately, there is always the fallback solution of requiring the implementor to enforce this
constraint at runtime.

 [rfc-eyepatch]: https://github.com/rust-lang/rfcs/blob/master/text/1327-dropck-param-eyepatch.md
 [rfc-nonparam]: https://github.com/rust-lang/rfcs/blob/master/text/1238-nonparametric-dropck.md
 [rfc-sound]: https://github.com/rust-lang/rfcs/blob/master/text/0769-sound-generic-drop.md