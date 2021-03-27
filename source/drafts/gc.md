---
layout: post
title: "A Tour of Safe Tracing GC Designs in Rust"
date: 2020-03-04 18:52:00 -0800
comments: true
categories: ["programming", "rust", "mozilla"]
---

I've been thinking about garbage collection in Rust for a long time, ever since I started working on [Servo]'s JS layer. I've [designed a GC library][rustgc-post], [worked on GC integration ideas for Rust itself][rust-design], worked on Servo's JS GC integration, and helped out with a [couple][josephine] [other][gc-arena] GC projects in Rust.

As a result, I tend to get pulled into GC discussions fairly often. I enjoy talking about GCs -- don't get me wrong -- but I often end up going over the same stuff. Being [lazy] I'd much prefer to be able to refer people to a single place where they can get up to speed on the general space of GC design, after which it's possible to have more in depth discussions about the specific tradeoffs necessary.

 [servo]: https://github.com/servo/servo
 [rustgc-post]: https://manishearth.github.io/blog/2015/09/01/designing-a-gc-in-rust/
 [rust-design]: https://manishearth.github.io/blog/2016/08/18/gc-support-in-rust-api-design/
 [josephine]: https://github.com/asajeffrey/josephine
 [gc-arena]: https://github.com/kyren/gc-arena
 [lazy]: https://manishearth.github.io/blog/2018/08/26/why-i-enjoy-blogging/#blogging-lets-me-be-lazy

### A note on terminology

A thing that often muddles discussions about GCs is that according to some definition of "GC", simple reference counting _is_ a GC. Typically the definition of GC used in academia broadly refers to any kind of automatic memory management. However, most programmers familiar with the term "GC" will usually liken it to "what Java, Go, Haskell, and C# do", which can be unambiguously referred to as _tracing_ garbage collection.

Tracing garbage collection is the kind which keeps track of which heap objects are directly reachable ("roots"), figures out the whole set of reachable heap objects ("tracing", also, "marking"), and then cleans them up ("sweeping").

Throughout this blog post I will use the term "GC" to exclusively refer to tracing garbage collection/collectors.

## Why write GCs for Rust?

(If you already want to write a GC in Rust and are reading this post to get ideas for _how_, you can skip this section. You already know why someone would want to write a GC for Rust)

Every time this topic is brought up someone will inevitably go "I thought the point of Rust was to avoid GCs" or "GCs will ruin Rust" or something. As a general rule it's good to not give too much weight to the comments section, but I think it's useful to explain why someone may wish for GC-like semantics in Rust.

There are really two distinct kinds of use cases. Firstly, sometimes you need to manage memory with cycles and `Rc<T>` is inadequate for the job since `Rc`-cycles get leaked. [`petgraph`][petgraph] or an [arena] are often acceptable solutions for this kind of pattern, but not always, especially if your data is super heterogeneous. This kind of thing crops up often when dealing with concurrent datastructures; for example [`crossbeam`][crossbeam] has [an epoch-based memory management system][crossbeam-epoch] which, while not a full tracing GC, has a lot of characteristics in common with GCs.

For the first use case it's rarely necessary to design a custom GC, you can look for a reusable crate like [`gc`][gc] [^1].

The second case is far more interesting in my experience, and since it cannot be solved by off-the-shelf solutions tends to crop up more often: integration with (or implementation of) programming languages that _do_ use a garbage collector. [Servo] needs to do this for integrating with the Spidermonkey JS engine and [luster] needed to do this for implementing the GC of its Lua VM.

Sometimes when integrating with a GCd language you can get away with not needing to implement a full garbage collector: JNI does this; while C++ does not have native garbage collection, JNI gets around this by simply rooting anything that crosses over to the C++ side[^2]. This is often fine!

The downside of this is that every interaction with objects managed by the GC has to go through an API call; you can't "embed" efficient Rust/C++ objects in the GC with ease. For example, in browsers most DOM types (e.g. [`Element`][servo-element]) are implemented in native code; and need to be able to contain references to other native GC'd types (it should be possible to inspect the [children of a `Node`][servo-node-child] without needing to call back into the JavaScript engine).

So sometimes you need to be able to integrate with a GC from a runtime; or even implement your own GC if you are writing a runtime that needs one.


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

## How would you even garbage collect without a runtime?

In most garbage collected languages, there's a runtime that controls all execution and is able to pause execution to run the GC whenever it likes.

Rust has a minimal runtime and can't do anything like this, especially not in a pluggable way your library can hook in to. For thread local GCs you basically have to write it such that GC operations (e.g. mutating a GC field, basically calling some subset of the APIs exposed by your GC library) are the only things that may trigger the garbage collector.

Concurrent GCs can trigger the GC on a separate thread but will typically need to block other threads whenever these threads attempt to perform a GC operation.

While this may restrict the flexibility of the garbage collector itself, this is actually pretty good for us from the side of API design: the garbage collection phase can only happen in certain well-known moments of the code, which means we only need to make things safe across _those_ boundaries. Many of the designs we shall look at build off of this observation.

## Tracing

Before getting into the actual examples of GC design, I want to point out a commonality of design between all of them: how they do tracing.

"Tracing" is the operation of traversing the graph of GC objects, starting from your roots and perusing their children, and their children's children, and so on.

In Rust, the easiest way to implement this is via a [custom derive]:


```rust
trait Trace {
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

I'm not going to get into the actual details of how mark-and-sweep algorithms work in this post; there are a lot of potential designs for them and they're not that interesting from the point of view of designing something a safe GC _API_ in Rust. However, the general idea is to keep a queue of found objects initially populated by the root, trace them to find new objects and queue them up if they've not already been traced. Clean up any objects that were _not_ found.


 [custom derive]: https://doc.rust-lang.org/book/ch19-06-macros.html#how-to-write-a-custom-derive-macro

## rust-gc

The [`gc`][gc] crate is one I wrote with [Nika Layzell] mostly as a fun exercise, to figure out if a safe GC API is _possible_. I've [written about the design in depth before][rustgc-post], but the essence of the design is that it does something similar to reference counting to keep track of roots, and forces all GC mutations go through special `GcCell` types so that they can update the root count:

```rust
struct Foo {
    bar: GcCell<Option<Gc<Bar>>>
}
// this is a root
let bar = Gc::new(Bar::new());
// this is also a root
let foo = Gc::new(Foo::new());
// .borrow_mut()'s RAII guard unroots bar
*foo.bar.borrow_mut() = Some(bar);
// foo is still a root here, no call to .set()
let v = vec![foo];
```

While this is essentially "free" on reads, this is a fair amount of reference count traffic on any kind of write, which might not be desired. Part of the goal of using GCs is to _avoid_ reference-counting-like patterns.

[`gc`][gc] is useful as a general-purpose GC if you just want a couple of things to participate in cycles without having to think about it too much. The general design can apply to a specialized GC integrating with another language runtime since it provides a clear way to keep track of roots; but it may not necessarily have the desired performance characteristics.

 [Nika Layzell]: https://twitter.com/kneecaw/

## Servo's DOM integration

[Servo][servo] is a browser engine in Rust that I used to work on full time. As mentioned earlier, browser engines typically implement a lot of their DOM types in native (i.e. Rust or C++, not JS) code, so for example [`Node`][servo-node] is a pure Rust object, and it [contains direct references to its children][servo-node-child] so Rust code can do things like traverse the tree without having to go back and forth between JS and Rust.

  [servo-node]: https://doc.servo.org/script/dom/element/struct.Element.html
