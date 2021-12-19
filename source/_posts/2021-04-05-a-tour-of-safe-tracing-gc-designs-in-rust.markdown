---
layout: post
title: "A Tour of Safe Tracing GC Designs in Rust"
date: 2021-04-05 08:32:30 -0700
comments: true
categories: ["mozilla", "programming", "rust"]
---

I've been thinking about garbage collection in Rust for a long time, ever since I started working on [Servo]'s JS layer. I've [designed a GC library][rustgc-post], [worked on GC integration ideas for Rust itself][rust-design], worked on Servo's JS GC integration, and helped out with a [couple][josephine] [other][gc-arena] GC projects in Rust.

As a result, I tend to get pulled into GC discussions fairly often. I enjoy talking about GCs -- don't get me wrong -- but I often end up going over the same stuff. Being [lazy] I'd much prefer to be able to refer people to a single place where they can get up to speed on the general space of GC design, after which it's possible to have more in depth discussions about the specific tradeoffs necessary.

I'll note that some of the GCs in this post are experiments or unmaintained. The goal of this post is to showcase these as examples of _design_, not necessarily general-purpose crates you may wish to use, though some of them are usable crates as well.

 [servo]: https://github.com/servo/servo
 [rustgc-post]: https://manishearth.github.io/blog/2015/09/01/designing-a-gc-in-rust/
 [rust-design]: https://manishearth.github.io/blog/2016/08/18/gc-support-in-rust-api-design/
 [josephine]: https://github.com/asajeffrey/josephine
 [gc-arena]: https://github.com/kyren/gc-arena
 [lazy]: https://manishearth.github.io/blog/2018/08/26/why-i-enjoy-blogging/#blogging-lets-me-be-lazy

### A note on terminology

A thing that often muddles discussions about GCs is that according to some definition of "GC", simple reference counting _is_ a GC. Typically the definition of GC used in academia broadly refers to any kind of automatic memory management. However, most programmers familiar with the term "GC" will usually liken it to "what Java, Go, Haskell, and C# do", which can be unambiguously referred to as _tracing_ garbage collection.

Tracing garbage collection is the kind which keeps track of which heap objects are directly reachable ("roots"), figures out the whole set of reachable heap objects ("tracing", also, "marking"), and then cleans them up ("sweeping").

Throughout this blog post I will use the term "GC" to refer to tracing garbage collection/collectors unless otherwise stated[^0].

 [^0]: I'm also going to completely ignore the field of _conservative_ stack-scanning tracing GCs where you figure out your roots by looking at all the stack memory and considering anything with a remotely heap-object-like bit pattern to be a root. These are interesting, but can't really be made 100% safe in the way Rust wants them to be unless you scan the heap as well.

## Why write GCs for Rust?

(If you already want to write a GC in Rust and are reading this post to get ideas for _how_, you can skip this section. You already know why someone would want to write a GC for Rust)

Every time this topic is brought up someone will inevitably go "I thought the point of Rust was to avoid GCs" or "GCs will ruin Rust" or something. As a general rule it's good to not give too much weight to the comments section, but I think it's useful to explain why someone may wish for GC-like semantics in Rust.

There are really two distinct kinds of use cases. Firstly, sometimes you need to manage memory with cycles and `Rc<T>` is inadequate for the job since `Rc`-cycles get leaked. [`petgraph`][petgraph] or an [arena] are often acceptable solutions for this kind of pattern, but not always, especially if your data is super heterogeneous. This kind of thing crops up often when dealing with concurrent datastructures; for example [`crossbeam`][crossbeam] has [an epoch-based memory management system][crossbeam-epoch] which, while not a full tracing GC, has a lot of characteristics in common with GCs.

For this use case it's rarely necessary to design a custom GC, you can look for a reusable crate like [`gc`][gc] [^1].

The second case is far more interesting in my experience, and since it cannot be solved by off-the-shelf solutions tends to crop up more often: integration with (or implementation of) programming languages that _do_ use a garbage collector. [Servo] needs to do this for integrating with the Spidermonkey JS engine and [luster] needed to do this for implementing the GC of its Lua VM. [boa], a pure Rust JS runtime, uses the [`gc`][gc] crate to back its garbage collector.

Sometimes when integrating with a GCd language you can get away with not needing to implement a full garbage collector: JNI does this; while C++ does not have native garbage collection, JNI gets around this by simply "rooting" (we'll cover what that means in a bit) anything that crosses over to the C++ side[^2]. This is often fine!

The downside of this is that every interaction with objects managed by the GC has to go through an API call; you can't "embed" efficient Rust/C++ objects in the GC with ease. For example, in browsers most DOM types (e.g. [`Element`][servo-element]) are implemented in native code; and need to be able to contain references to other native GC'd types (it should be possible to inspect the [children of a `Node`][servo-node-child] without needing to call back into the JavaScript engine).

So sometimes you need to be able to integrate with a GC from a runtime; or even implement your own GC if you are writing a runtime that needs one. In both of these cases you typically want to be able to safely manipulate GC'd objects from Rust code, and even directly put Rust types on the GC heap.


 [petgraph]: https://docs.rs/petgraph/
 [arena]: https://manishearth.github.io/blog/2021/03/15/arenas-in-rust/
 [crossbeam]: https://docs.rs/crossbeam/
 [crossbeam-epoch]: https://docs.rs/crossbeam/0.8.0/crossbeam/epoch/index.html
 [gc]: https://docs.rs/gc/
 [^1]: Which currently does not have support for concurrent garbage collection, but it could be added.
 [^2]: Some JNI-using APIs are also forced to have [explicit rooting APIs](https://developer.android.com/ndk/reference/group/bitmap#androidbitmap_lockpixels) to give access to things like raw buffers.
 [luster]: https://github.com/kyren/luster
 [servo-element]: https://doc.servo.org/script/dom/element/struct.Element.html
 [servo-node-child]: https://doc.servo.org/script/dom/node/struct.Node.html#structfield.child_list
 [boa]: https://github.com/jasonwilliams/boa/

## Why are GCs in Rust hard?

In one word: Rooting. In a garbage collector, the objects "directly" in use on the stack are the "roots", and you need to be able to identify them. Here, when I say "directly", I mean "accessible without having to go through other GC'd objects", so putting an object inside a `Vec<T>` does not make it stop being a root, but putting it inside some other GC'd object does.

Unfortunately, Rust doesn't really have a concept of "directly on the stack":

```rust
struct Foo {
    bar: Option<Gc<Bar>>
}
// this is a root
let bar = Gc::new(Bar::new());
// this is also a root
let foo = Gc::new(Foo::new());
// bar should no longer be a root (but we can't detect that!)
foo.bar = Some(bar);
// but foo should still be a root here since it's not inside
// another GC'd object
let v = vec![foo];
```

Rust's ownership system actually makes it easier to have fewer roots since it's relatively easy to state that taking `&T` of a GC'd object doesn't need to create a new root, and let Rust's ownership system sort it out, but being able to distinguish between "directly owned" and "indirectly owned" is super tricky.

Another aspect of this is that garbage collection is really a moment of global mutation -- the garbage collector reads through the heap and then deletes some of the objects there. This is a moment of the rug being pulled out under your feet. Rust's entire design is predicated on such rug-pulling being _very very bad and not to be allowed_, so this can be a bit problematic. This isn't as bad as it may initially sound because after all the rug-pulling is mostly just cleaning up unreachable objects, but it does crop up a couple times when fitting things together, especially around destructors and finalizers[^3]. Rooting would be far easier if, for example, you were able to declare areas of code where "no GC can happen"[^4] so you can tightly scope the rug-pulling and have to worry less about roots.


 [^3]: In general, finalizers in GCs are hard to implement soundly in any language, not just Rust, but Rust can sometimes be a bit more annoying about it.
 [^4]: Spolier: This is actually possible in Rust, and we'll get into it further in this post!


### Destructors and finalizers

It's worth calling out destructors in particular. A huge problem with custom destructors on GCd types is that the custom destructor totally can stash itself away into a long-lived reference during garbage collection, leading to a dangling reference:

```rust
struct LongLived {
    dangle: RefCell<Option<Gc<CantKillMe>>>
}

struct CantKillMe {
    // set up to point to itself during construction
    self_ref: RefCell<Option<Gc<CantKillMe>>>
    long_lived: Gc<LongLived>
}

impl Drop for CantKillMe {
    fn drop(&mut self) {
        // attach self to long_lived
        *self.long_lived.dangle.borrow_mut() = Some(self.self_ref.borrow().clone().unwrap());
    }
}

let long = Gc::new(LongLived::new());
{
    let cant = Gc::new(CantKillMe::new());
    *cant.self_ref.borrow_mut() = Some(cant.clone());
    // cant goes out of scope, CantKillMe::drop is run
    // cant is attached to long_lived.dangle but still cleaned up
}

// Dangling reference!
let dangling = long.dangle.borrow().unwrap();
```

The most common  solution here is to disallow destructors on types that use `#[derive(Trace)]`, which can be done by having the custom derive generate a `Drop` implementation, or have it generate something which causes a conflicting type error.

You can additionally provide a `Finalize` trait that has different semantics: the GC calls it while cleaning up GC objects, but it may be called multiple times or not at all. This kind of thing is typical in GCs outside of Rust as well.


## How would you even garbage collect without a runtime?

In most garbage collected languages, there's a runtime that controls all execution, knows about every variable in the program, and is able to pause execution to run the GC whenever it likes.

Rust has a minimal runtime and can't do anything like this, especially not in a pluggable way your library can hook in to. For thread local GCs you basically have to write it such that GC operations (things like mutating a GC field; basically some subset of the APIs exposed by your GC library) are the only things that may trigger the garbage collector.

Concurrent GCs can trigger the GC on a separate thread but will typically need to pause other threads whenever these threads attempt to perform a GC operation that could potentially be invalidated by the running garbage collector.

While this may restrict the flexibility of the garbage collector itself, this is actually pretty good for us from the side of API design: the garbage collection phase can only happen in certain well-known moments of the code, which means we only need to make things safe across _those_ boundaries. Many of the designs we shall look at build off of this observation.

## Commonalities

Before getting into the actual examples of GC design, I want to point out some commonalities of design between all of them, especially around how they do tracing:

### Tracing

"Tracing" is the operation of traversing the graph of GC objects, starting from your roots and perusing their children, and their children's children, and so on.

In Rust, the easiest way to implement this is via a [custom derive]:


```rust
// unsafe to implement by hand since you can get it wrong
unsafe trait Trace {
    fn trace(&mut self, gc_context: &mut GcContext);
}

#[derive(Trace)]
struct Foo {
    vec: Vec<Gc<Bar>>,
    extra_thing: Gc<Baz>,
    just_a_string: String
}
```

The custom derive of `Trace` basically just calls `trace()` on all the fields. `Vec`'s `Trace` implementation will be written to call `trace()` on all of its fields, and `String`'s `Trace` implementation will do nothing. `Gc<T>` will likely have a `trace()` that marks its reachability in the `GcContext`, or something similar.

This is a pretty standard pattern, and while the specifics of the `Trace` trait will typically vary, the general idea is roughly the same.

I'm not going to get into the actual details of how mark-and-sweep algorithms work in this post; there are a lot of potential designs for them and they're not that interesting from the point of view of designing a safe GC _API_ in Rust. However, the general idea is to keep a queue of found objects initially populated by the root, trace them to find new objects and queue them up if they've not already been traced. Clean up any objects that were _not_ found.

 [custom derive]: https://doc.rust-lang.org/book/ch19-06-macros.html#how-to-write-a-custom-derive-macro

### Immutable-by-default

Another commonality between these designs is that a `Gc<T>` is always potentially shared, and thus will need tight control over mutability to satisfy Rust's ownership invariants. This is typically achieved by using interior mutability, much like how `Rc<T>` is almost always paired with `RefCell<T>` for mutation, however some approaches (like that in [josephine]) do allow for mutability without runtime checking.

### Threading

Some GCs are single-threaded, and some are multi-threaded. The single threaded ones typically have a `Gc<T>` type that is not `Send`, so while you can set up multiple graphs of GC types on different threads, they're essentially independent. Garbage collection only affects the thread it is being performed for, all other threads can continue unhindered.

Multithreaded GCs will have a `Send` `Gc<T>` type. Garbage collection will typically, but not always, block any thread which attempts to access data managed by the GC during that time. In some languages there are "stop the world" garbage collectors which block all threads at "safepoints" inserted by the compiler; Rust does not have the capability to insert such safepoints and blocking threads on GCs is done at the library level.

Most of the examples below are single-threaded, but their API design is not hard to extend towards a hypothetical multithreaded GC.


## rust-gc

The [`gc`][gc] crate is one I wrote with [Nika Layzell] mostly as a fun exercise, to figure out if a safe GC API is _possible_. I've [written about the design in depth before][rustgc-post], but the essence of the design is that it does something similar to reference counting to keep track of roots, and forces all GC mutations go through special `GcCell` types so that they can update the root count. Basically, a "root count" is updated whenever something becomes a root or stops being a root:

```rust
struct Foo {
    bar: GcCell<Option<Gc<Bar>>>
}
// this is a root (root count = 1)
let bar = Gc::new(Bar::new());
// this is also a root (root count = 1)
let foo = Gc::new(Foo::new());
// .borrow_mut()'s RAII guard unroots bar (sets its root count to 0)
*foo.bar.borrow_mut() = Some(bar);
// foo is still a root here, no call to .set()
let v = vec![foo];

// at destrucion time, foo's root count is set to 0
```

The actual garbage collection phase will occur when certain GC operations are performed at a time when the heap is considered to have gotten reasonably large according to some heuristics.

While this is essentially "free" on reads, this is a fair amount of reference count traffic on any kind of write, which might not be desired; often the goal of using GCs is to _avoid_ the performance characteristics of reference-counting-like patterns. Ultimately this is a hybrid approach that's a mix of tracing and reference counting[^10].

[`gc`][gc] is useful as a general-purpose GC if you just want a couple of things to participate in cycles without having to think about it too much. The general design can apply to a specialized GC integrating with another language runtime since it provides a clear way to keep track of roots; but it may not necessarily have the desired performance characteristics.

 [Nika Layzell]: https://twitter.com/kneecaw/
 [unified-bacon]: https://courses.cs.washington.edu/courses/cse590p/05au/p50-bacon.pdf
 [^10]: Such hybrid approaches are common in high performance GCs; _<a href="https://courses.cs.washington.edu/courses/cse590p/05au/p50-bacon.pdf">"A Unified Theory of Garbage Collection"</a>_ by Bacon et al. covers a lot of the breadth of these approaches.


## Servo's DOM integration

[Servo][servo] is a browser engine in Rust that I used to work on full time. As mentioned earlier, browser engines typically implement a lot of their DOM types in native (i.e. Rust or C++, not JS) code, so for example [`Node`][servo-node] is a pure Rust object, and it [contains direct references to its children][servo-node-child] so Rust code can do things like traverse the tree without having to go back and forth between JS and Rust.


Servo's model is a little weird: roots are a _different type_, and lints enforce that unrooted heap references are never placed on the stack:

```rust
#[dom_struct] // this is #[derive(JSTraceable)] plus some markers for lints
pub struct Node {
    // the parent type, for inheritance
    eventtarget: EventTarget,
    // in the actual code this is a different helper type that combines
    // the RefCell, Option, and Dom, but i've simplified it to use
    // stdlib types for this example
    prev_sibling: RefCell<Option<Dom<Node>>>,
    next_sibling: RefCell<Option<Dom<Node>>>,
    // ...
}

impl Node {
    fn frob_next_sibling(&self) {
        // fields can be accessed as borrows without any rooting
        if let Some(next) = self.next_sibling.borrow().as_ref() {
            next.frob();
        }
    }

    fn get_next_sibling(&self) -> Option<DomRoot<Node>> {
        // but you need to root things for them to escape the borrow
        // .root() turns Dom<T> into DomRoot<T>
        self.next_sibling.borrow().as_ref().map(|x| x.root())
    }

    fn illegal(&self) {
        // this line of code would get linted by a custom lint called unrooted_must_root
        // (which works somewhat similarly to the must_use stuff that Rust does)
        let ohno: Dom<Node> = self.next_sibling.borrow_mut().take();
    }
}
```

`Dom<T>` is basically a smart pointer that behaves like `&T` but without a lifetime, whereas `DomRoot<T>` has the additional behavior of rooting on creation (and unrooting on `Drop`). The custom lint plugin essentially enforces that `Dom<T>`, and any DOM structs (tagged with `#[dom_struct]`) are never accessible on the stack aside from through `DomRoot<T>` or `&T`.

I wouldn't recommend this approach; it works okay but we've wanted to move off of it for a while because it relies on custom plugin lints for soundness. But it's worth mentioning for completeness.

  [servo-node]: https://doc.servo.org/script/dom/element/struct.Element.html

## Josephine (Servo's experimental GC plans)

Given that Servo's existing GC solution depends on plugging in to the compiler to do additional static analysis, we wanted something better. So [Alan] designed [Josephine] ("JS affine"), which uses Rust's affine types and borrowing in a cleaner way to provide a safe GC system.

Josephine is explicitly designed for Servo's use case and as such does a lot of neat things around "compartments" and such that are probably irrelevant unless you specifically wish for your GC to integrate with a JS engine.

I mentioned earlier that the fact that the garbage collection phase can only happen in certain well-known moments of the code actually can make things easier for GC design, and Josephine is an example of this.

Josephine has a "JS context", which is to be passed around everywhere and essentially represents the GC itself. When doing operations which may trigger a GC, you have to borrow the context mutably, whereas when accessing heap objects you need to borrow the context immutably. You can root heap objects to remove this requirement:

```rust
// cx is a `JSContext`, `node` is a `JSManaged<'a, C, Node>`
// assuming next_sibling and prev_sibling are not Options for simplicity

// borrows cx for `'b`
let next_sibling: &'b Node = node.next_sibling.borrow(cx);
println!("Name: {:?}", next_sibling.name);
// illegal, because cx is immutably borrowed by next_sibling
// node.prev_sibling.borrow_mut(cx).frob();

// read from next_sibling to ensure it lives this long
println!("{:?}", next_sibling.name);

let ref mut root = cx.new_root();
// no longer needs to borrow cx, borrows root for 'root instead
let next_sibling: JSManaged<'root, C, Node> = node.next_sibling.in_root(root);
// now it's fine, no outstanding borrows of `cx`
node.prev_sibling.borrow_mut(cx).frob();

// read from next_sibling to ensure it lives this long
println!("{:?}", next_sibling.name);
```

`new_root()` creates a new root, and `in_root` ties the lifetime of a JS managed type to the root instead of to the `JSContext` borrow, releasing the borrow of the `JSContext` and allowing it to be borrowed mutably in future `.borrow_mut()` calls.

Note that `.borrow()` and `.borrow_mut()` here do not have runtime borrow-checking cost despite their similarities to `RefCell::borrow()`, they instead are doing some lifetime juggling to make things safe. Creating roots typically does have runtime cost. Sometimes you _may_ need to use `RefCell<T>` for the same reason it's used in `Rc`, but mostly only for non-GCd fields.

Custom types are typically defined in two parts as so:

```rust
#[derive(Copy, Clone, Debug, Eq, PartialEq, JSTraceable, JSLifetime, JSCompartmental)]
pub struct Element<'a, C> (pub JSManaged<'a, C, NativeElement<'a, C>>);

#[derive(JSTraceable, JSLifetime, JSCompartmental)]
pub struct NativeElement<'a, C> {
    name: JSString<'a, C>,
    parent: Option<Element<'a, C>>,
    children: Vec<Element<'a, C>>,
}
```

where `Element<'a>` is a convenient copyable reference that is to be used inside other GC types, and `NativeElement<'a>` is its backing storage. The `C` parameter has to do with compartments and can be ignored for now.

A neat thing worth pointing out is that there's no runtime borrow checking necessary for manipulating other GC references, even though roots let you hold multiple references to the same object!

```rust
let parent_root = cx.new_root();
let parent = element.borrow(cx).parent.in_root(parent_root);
let ref mut child_root = cx.new_root();

// could potentially be a second reference to `element` if it was
// the first child
let first_child = parent.children[0].in_root(child_root);

// this is okay, even though we hold a reference to `parent`
// via element.parent, because we have rooted that reference so it's
// now independent of whether `element.parent` changes!
first_child.borrow_mut(cx).parent = None;
```

Essentially, when mutating a field, you have to obtain mutable access to the context, so there will not be any references to the field itself still around (e.g. `element.borrow(cx).parent`), only to the GC'd data within it, so you can change what a field references without invalidating other references to the _contents_ of what the field references. This is a pretty cool trick that enables GC _without runtime-checked interior mutability_, which is relatively rare in such designs.


 [Alan]: https://github.com/asajeffrey/
 [Josephine]: https://github.com/asajeffrey/josephine

## Unfinished design for a builtin Rust GC

For a while a couple of us worked on a way to make Rust _itself_ extensible with a pluggable GC, using LLVM stack map support for finding roots. After all, if we know which types are GC-ish, we can include metadata on how to find roots for each function, similar to how Rust functions currently contain unwinding hooks to enable cleanly running destructors during a panic.

We never got around to figuring out a _complete_ design, but you can find more information on what we figured out in [my][rust-design] and [Felix's][felix-rust-design] posts on this subject. Essentially, it involved a `Trace` trait with more generic `trace` methods, an auto-implemented `Root` trait that works similar to `Send`, and compiler machinery to keep track of which `Root` types are on the stack.

This is probably not too useful for people attempting to implement a GC, but I'm mentioning it for completeness' sake.

Note that pre-1.0 Rust did have a builtin GC (`@T`, known as "managed pointers"), but IIRC in practice the cycle-management parts were not ever implemented so it behaved exactly like `Rc<T>`. I believe it was intended to have a cycle collector (I'll talk more about that in the next section).

 [felix-rust-design]: http://blog.pnkfx.org/blog/categories/gc/

## bacon-rajan-cc (and cycle collectors in general)

[Nick Fitzgerald][fitzgen] wrote [`bacon-rajan-cc`][bacon-rajan-cc] to implement _["Concurrent Cycle Collection in Reference Counted Systems"][bacon-rajan]__ by David F. Bacon and V.T. Rajan.

This is what is colloquially called a _cycle collector_; a kind of garbage collector which is essentially "what if we took `Rc<T>` but made it detect cycles". Some people do not consider these to be _tracing_ garbage collectors, but they have a lot of similar characteristics (and they do still "trace" through types). They're often categorized as "hybrid" approaches, much like [`gc`][gc].

The idea is that you don't actually need to _know_ what the roots are if you're maintaining reference counts: if a heap object has a reference count that is more than the number of heap objects referencing it, it must be a root. In practice it's pretty inefficient to traverse the entire heap, so optimizations are applied, often by applying different "colors" to nodes, and by only looking at the set of objects that have recently have their reference counts decremented.

A crucial observation here is that if you _only focus on potential garbage_, you can shift your definition of "root" a bit, when looking for cycles you don't need to look for references from the stack, you can be satisfied with references from _any part of the heap you know for a fact is reachable from things which are not potential garbage_.

A neat property of cycle collectors is while mark and sweep tracing GCs have their performance scale by the size of the heap as a whole, cycle collectors scale by the size of _the actual garbage you have_ [^5]. There are of course other tradeoffs:  deallocation is often cheaper or "free" in tracing GCs (amortizing those costs by doing it during the sweep phase) whereas cycle collectors have the constant allocator traffic involved in cleaning up objects when refcounts reach zero.

The way [bacon-rajan-cc] works is that every time a reference count is decremented, the object is added to a list of "potential cycle roots", unless the reference count is decremented to 0 (in which case the object is immediately cleaned up, just like `Rc`). It then traces through this list; decrementing refcounts for every reference it follows, and cleaning up any elements that reach refcount 0. It then traverses this list _again_ and reincrements refcounts for each reference it follows, to restore the original refcount. This basically treats any element not reachable from this "potential cycle root" list as "not garbage", and doesn't bother to visit it.

Cycle collectors require tighter control over the garbage collection algorithm, and have differing performance characteristics, so they may not necessarily be suitable for all use cases for GC integration in Rust, but it's definitely worth considering!


 [bacon-rajan-cc]: https://github.com/fitzgen/bacon-rajan-cc
 [fitzgen]: https://fitzgeraldnick.com/
 [bacon-rajan]: https://researcher.watson.ibm.com/researcher/files/us-bacon/Bacon01Concurrent.pdf
 [^5]: Firefox's DOM actually uses a mark & sweep tracing GC _mixed with_ a cycle collector for this reason. The DOM types themselves are cycle collected, but JavaScript objects are managed by the Spidermonkey GC. Since some DOM types may contain references to arbitrary JS types (e.g. ones that store callbacks) there's a fair amount of work required to break cycles manually in some cases, but it has performance benefits since the vast majority of DOM objects either never become garbage or become garbage by having a couple non-cycle-participating references get released.

## cell-gc

[Jason Orendorff][jorendorff]'s [cell-gc] crate is interesting, it has a concept of "heap sessions". Here's a modified example from the readme:

```rust
use cell_gc::Heap;

// implements IntoHeap, and also generates an IntListRef type and accessors
#[derive(cell_gc_derive::IntoHeap)]
struct IntList<'h> {
    head: i64,
    tail: Option<IntListRef<'h>>
}

fn main() {
    // Create a heap (you'll only do this once in your whole program)
    let mut heap = Heap::new();

    heap.enter(|hs| {
        // Allocate an object (returns an IntListRef)
        let obj1 = hs.alloc(IntList { head: 17, tail: None });
        assert_eq!(obj1.head(), 17);
        assert_eq!(obj1.tail(), None);

        // Allocate another object
        let obj2 = hs.alloc(IntList { head: 33, tail: Some(obj1) });
        assert_eq!(obj2.head(), 33);
        assert_eq!(obj2.tail().unwrap().head(), 17);

        // mutate `tail`
        obj2.set_tail(None);
    });
}
```

All mutation goes through autogenerated accessors, so the crate has a little more control over traffic through the GC. These accessors help track roots via a scheme similar to what [`gc`][gc] does; where there's an `IntoHeap` trait used for modifying root refcounts when a reference is put into and taken out of the heap via accessors.

Heap sessions allow for the heap to moved around, even sent to other threads, and their lifetime prevents heap objects from being mixed between sessions. This uses a concept called _generativity_; you can read more about generativity in _["You Can't Spell Trust Without Rust"][thesis] ch 6.3, by [Alexis Beingessner][gankra], or by looking at the [`indexing`] crate.

 [cell-gc]: https://github.com/jorendorff/cell-gc
 [jorendorff]: https://github.com/jorendorff/

## Interlude: The similarities between `async` and GCs

The next two examples use machinery from Rust's `async` functionality despite having nothing to do with async I/O, and I think it's important to talk about why that should make sense. I've [tweeted about this before][manish-async-tweet]: I and [Catherine West][kyren] figured this out when we were talking about [her GC idea][gc-arena] based on `async`.

You can see some of this correspondence in Go: Go is a language that has both garbage collection and async I/O, and both of these use the same "safepoints" for yielding to the garbage collector or the scheduler. In Go, the compiler needs to automatically insert code that checks the "pulse" of the heap every now and then, and potentially runs garbage collection. It also needs to automatically insert code that can tell the scheduler "hey now is a safe time to interrupt me if a different goroutine wishes to run". These are very similar in principle -- they're both essentially places where the compiler is inserting "it is okay to interrupt me now" checks, sometimes called "interruption points" or "yield points".

Now, Rust's compiler does not automatically insert interruption points. However, the design of `async` in Rust is essentially a way of adding _explicit_ interruption points to Rust. `foo().await` in Rust is a way of running `foo()` and expecting that the scheduler _may_ interrupt the code in between. The design of [`Future`][future] and [`Pin<P>`][pin-p] come out of making this safe and pleasant to work with.

As we shall see, this same machinery can be used for creating safe interruption points for GCs in Rust.


 [manish-async-tweet]: https://twitter.com/ManishEarth/status/1073651552768819200
 [kyren]: https://github.com/kyren
 [pin-p]: https://doc.rust-lang.org/nightly/std/pin/struct.Pin.html
 [future]: https://doc.rust-lang.org/nightly/std/future/trait.Future.html

## Shifgrethor

[shifgrethor] is an experiment by [Saoirse][withoutboats] to try and build a GC that uses [`Pin<P>`][pin-p] for managing roots. They've written extensively on the design of [shifgrethor][shifgrethor] [on their blog][shif-blog]. In particular, the [post on rooting][shif-root] goes through how rooting works.

The basic design is that there's a `Root<'root>` type that contains a `Pin<P>`, which can be _immovably_ tied to a stack frame using the same idea behind `pin-utils`' [`pin_mut!()` macro][pin-mut]:

```rust
letroot!(root);
let gc: Gc<'root, Foo> = root.gc(Foo::new());
```

The fact that `root` is immovable allows for it to be treated as a true marker for the _stack frame_ over anything else. The list of rooted types can be neatly stored in an ordered stack-like vector in the GC implementation, popping when individual roots go out of scope.

If you wish to return a rooted object from a function, the function needs to accept a `Root<'root>`:

```rust
fn new<'root>(root: Root<'root>) -> Gc<'root, Self> {
    root.gc(Self {
        // ...
    }
}
```

All GC'd types have a `'root` lifetime of the root they trace back to, and are declared with a custom derive:

```rust
#[derive(GC)]
struct Foo<'root> {
    #[gc] bar: GcStore<'root, Bar>,
}
```

`GcStore` is a way to have fields use the rooting of their parent. Normally, if you wanted to put `Gc<'root2, Bar<'root2>>` inside `Foo<'root1>` you would not be able to because the lifetimes derive from different roots. `GcStore`, along with autogenerated accessors from `#[derive(GC)]`, will set `Bar`'s lifetime to be the same as `Foo` when you attempt to stick it inside `Foo`.


This design is somewhat similar to that of Servo where there's a pair of types, one that lets us refer to GC types on the stack, and one that lets GC types refer to each other on the heap, but it uses `Pin<P>` instead of a lint to enforce this safely, which is way nicer. `Root<'root>` and `GcStore` do a bunch of lifetime tweaking that's reminiscent of Josephine's rooting system, however there's no need for an `&mut JsContext` type that needs to be passed around everywhere.


 [shifgrethor]: https://github.com/withoutboats/shifgrethor
 [withoutboats]: https://github.com/withoutboats/
 [shif-blog]: https://without.boats/tags/shifgrethor/
 [shif-root]: https://without.boats/blog/shifgrethor-iii/
 [pin-mut]: https://docs.rs/pin-utils/0.1.0/pin_utils/macro.pin_mut.html

## gc-arena

[`gc-arena`][gc-arena] is [Catherine West][kyren]'s experimental GC design for her Lua VM, [`luster`][luster].

The `gc-arena` crate forces all GC-manipulating code to go within `arena.mutate()` calls, between which garbage collection may occur.

```rust
#[derive(Collect)]
#[collect(no_drop)]
struct TestRoot<'gc> {
    number: Gc<'gc, i32>,
    many_numbers: GcCell<Vec<Gc<'gc, i32>>>,
}

make_arena!(TestArena, TestRoot);

let mut arena = TestArena::new(ArenaParameters::default(), |mc| TestRoot {
    number: Gc::allocate(mc, 42),
    many_numbers: GcCell::allocate(mc, Vec::new()),
});

arena.mutate(|_mc, root| {
    assert_eq!(*((*root).number), 42);
    root.numbers.write(mc).push(Gc::allocate(mc, 0));
});
```

Mutation is done with `GcCell`, basically a fancier version of `Gc<RefCell<T>>`. All GC operations require a `MutationContext` (`mc`), which is only available within `arena.mutate()`. 

Only the arena root may survive between `mutate()` calls, and garbage collection does not happen during `.mutate()`, so rooting is easy -- just follow the arena root. This crate allows for multiple GCs to coexist with separate heaps, and, similarly to [cell-gc], it uses generativity to enforce that the heaps do not get mixed.

So far this is mostly like other arena-based systems, but with a GC.

The _really cool_ part of the design is the `gc-sequence` crate, which essentially builds a `Future`-like API (using a `Sequence` trait) on top of `gc-arena` that can potentially make this very pleasant to use. Here's a modified example from a test:

```rust
#[derive(Collect)]
#[collect(no_drop)]
struct TestRoot<'gc> {
    test: Gc<'gc, i32>,
}

make_sequencable_arena!(test_sequencer, TestRoot);
use test_sequencer::Arena as TestArena;

let arena = TestArena::new(ArenaParameters::default(), |mc| TestRoot {
    test: Gc::allocate(mc, 42),
});

let mut sequence = arena.sequence(|root| {
    sequence::from_fn_with(root.test, |_, test| {
        if *test == 42 {
            Ok(*test + 10)
        } else {
            Err("will not be generated")
        }
    })
    .and_then(|_, r| Ok(r + 12))
    .and_chain(|_, r| Ok(sequence::ok(r - 10)))
    .then(|_, res| res.expect("should not be error"))
    .chain(|_, r| sequence::done(r + 10))
    .map(|r| sequence::done(r - 60))
    .flatten()
    .boxed()
});

loop {
    match sequence.step() {
        Ok((_, output)) => {
            assert_eq!(output, 4);
            return;
        }
        Err(s) => sequence = s,
    }
}
```

This is _very_ similar to chained callback futures code; and if it could use the `Future` trait would be able to make use of `async` to convert this callback heavy code into sequential code with interrupt points using `await`. There were design constraints making `Future` not workable for this use case, though if Rust ever gets generators this would work well, and it's quite possible that another GC with a similar design could be written, using `async`/`await` and `Future`.

Essentially, this paints a picture of an entire space of Rust GC design where GC mutations are performed using `await` (or `yield` if we ever get generators), and garbage collection can occur during those yield points, in a way that's highly reminiscent of Go's design.

 [luster]: https://github.com/kyren/luster
 [thesis]: https://raw.githubusercontent.com/Gankra/thesis/master/thesis.pdf
 [gankra]: https://github.com/Gankra
 [`indexing`]: https://github.com/bluss/indexing

## Moving forward

As is hopefully obvious, the space of safe GC design in Rust is quite rich and has a lot of interesting ideas. I'm really excited to see what folks come up with here!

If you're interested in reading more about GCs in general, _["A Unified Theory of Garbage Collection"][bacon-unified]_ by Bacon et al and the [GC Handbook][gchandbook] are great reads.

_Thanks to [Andi McClure][mcc], [Jason Orendorff][jorendorff], [Nick Fitzgerald][fitzgen], and [Nika Layzell] for providing feedback on drafts of this blog post_


 [jorendorff]: https://twitter.com/jorendorff/
 [bacon-unified]: https://courses.cs.washington.edu/courses/cse590p/05au/p50-bacon.pdf
 [gchandbook]: http://gchandbook.org/
 [mcc]: https://mermaid.industries/
