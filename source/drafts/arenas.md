---
layout: post
title: "Arenas in Rust"
date: 2021-03-14 10:00:00 -0800
comments: true
categories: ["programming", "rust"]
---

There's been some discussion about arenas in Rust recently.

Arenas aren't something you would typically reach for in Rust so fewer people know about them, and you only really see them in applications for various niche use cases. Usually you can use an arena by pulling in a crate and not using additional `unsafe`, so there's no need to be particularly skittish around them in Rust, and it seems like it would be useful knowledge, especially for people coming to Rust fields where arenas are more common.

Furthermore, there's a set of _really cool_ lifetime effects involved when implementing self-referential arenas, that I don't think have been written about before.

I'm mostly writing this to talk about the cool lifetime effects, but I figured it's worth writing a general introduction that has something for all Rustaceans. If you know what arenas are and just want the cool lifetimes you can jump directly to [the section on implementing self-referential arenas][section-3].

 [section-3]: #implementing-a-self-referential-arena

## What's an arena?

An arena is essentially a way to group up allocations that are expected to have the same lifetime. Quite often you need to allocate a bunch of objects for the lifetime of an event, after which they can all be thrown away wholesale. It's inefficient to call into the system allocator each time, and far more preferable to _preallocate_ a bunch of memory for your objects, cleaning it all up at once once you're done with them as a whole.

Broadly speaking, there are two reasons you might wish to use an arena:

Firstly, your primary goal may be to reduce allocation pressure, as mentioned above. For example, in a game or application, there may be large mishmash of per-frame-tick objects that need to get allocated each frame, and then thrown away. This is _extremely_ common in game development in particular, and allocator pressure is something gamedevs tend to care about. It's easy enough to allocate an arena, fill it up during each frame and clear it out once the frame is over. This has additional benefits of cache locality; you can ensure that most of the per-frame objects (which are likely used more often than other objects) are usually in cache during the frame, since they've been allocated adjacently.

Another goal might be that you want to write self referential data, like a complex graph with cycles, that can get cleaned up all at once. For example, when writing compilers, type information will likely need to reference other types and other such data, leading to a complex, potentially cyclic graph of types. Once you've computed a type you probably don't need to throw it away individually, so you can use an arena to store all your computed type information, cleaning the whole thing up at once when you're at a stage where the types don't matter anymore. Using this pattern allows your code to not have to worry about whether the self-referential bits get deallocated "early", it lets you make the assumption that if you have a `Ty` it lives as long as all the other `Ty`s and can reference them directly.

These two goals are not necessarily disjoint: You may wish to use an arena to achieve both goals simultaneously. But you can also just have an arena that disallows self referential types (but has other nice properties). Later in this post I'm going to implement an arena that allows self-referential types but is not great on allocation pressure, mostly for ease of implementation. _Typically_ if you're writing an arena for self-referential types you can make it simultaneously reduce allocator pressure, but there can be tradeoffs.

## How can I use an arena in Rust?

Typically to _use_ an arena you can just pull in a crate that implements the right kind of arena. There are two that I know of that I'll talk about below, though [a cursory search of "arena" on crates.io][crates-search] turns up many other promising candidates.

I'll also quickly note that if you just need cyclic graph structures, you don't _have_ to use an arena, the [`petgraph`] crate is often sufficient.

 [`petgraph`]: https://docs.rs/petgraph/

### Bumpalo

[`Bumpalo`] is a fast "bump allocator", which allows heterogenous contents (but not cyclic references).

```rust
use bumpalo::Bump;

// (example slightly modified from `bumpalo` docs)

// Create a new arena to bump allocate into.
let bump = Bump::new();

// Allocate values into the arena.
let scooter = bump.alloc(Doggo {
    cuteness: u64::max_value(),
    age: 8,
    scritches_required: true,
});

// Happy birthday, Scooter!
scooter.age += 1;
```

Every call to `Bump::alloc()` returns a mutable reference to the allocated object. You can allocate different objects, and they can even reference each other (but not in a cyclic way; the borrow checker will enforce this). By default it does not call destructors on its contents; however you can use [`bumpalo::boxed`][bumpalo::boxed] (or custom allocators on Nightly) to get this behavior. You can similarly use [`bumpalo::collections`][bumpalo::collections] to get `bumpalo`-backed vectors and strings.

Rust does support swapping out the global allocator used by `Box`, `Vec`, `HashMap`, etc using `#![global_allocator]`; and [`bumpalo`] supports being used in this way, so this crate is also useful for environments where you just need a fast bump allocator (e.g. light allocation in WASM).

 [crates-search]: https://crates.io/search?q=arena
 [`bumpalo`]: https://docs.rs/bumpalo
 [bumpalo::boxed]: https://docs.rs/bumpalo/3.6.1/bumpalo/boxed/index.html
 [bumpalo::collections]: https://docs.rs/bumpalo/3.6.1/bumpalo/collections/index.html

### `typed-arena`

[`typed-arena`] is an arena allocator that can only store objects of a single type, but it does allow for setting up cyclic references:

```rust
// Example from typed-arena docs

use std::cell::Cell;
use typed_arena::Arena;

struct CycleParticipant<'a> {
    other: Cell<Option<&'a CycleParticipant<'a>>>,
}

let arena = Arena::new();

let a = arena.alloc(CycleParticipant { other: Cell::new(None) });
let b = arena.alloc(CycleParticipant { other: Cell::new(None) });

// mutate them after the fact to set up a cycle
a.other.set(Some(b));
b.other.set(Some(a));
```

Unlike `bumpalo`, `typed-arena` will always run destructors on its contents when the arena itself goes out of scope[^1]


 [`typed-arena`]: https://docs.rs/typed-arena/
 [^1]: You may wonder how it is safe for destructors to be safely run on cyclic references -- after all, the destructor of whichever entry gets destroyed second will be able to read a dangling reference. We'll cover this later in the post but it has to do with drop check, and specifically that if you attempt to set up cycles, the only explicit destructors allowed on the arena entries themselves will be <a href="https://doc.rust-lang.org/nomicon/dropck.html#an-escape-hatch">ones that use `#![may_dangle]`</a>.

## Implementing a self-referential arena

Self referential arenas are interesting because, typically, Rust is very very wary of self-referential data. But arenas let you clearly separate the step of "I don't care about this object" and "this object can be deleted" in a way that is sufficient to allow self-referential and cyclic types.

The key to implementing an arena `Arena` with entries typed as `Entry` is in the following rules:

 - `Arena` and `Entry` should both have a lifetime parameter: `Arena<'entry>` and `Entry<'entry>`
 - `Arena` methods should all receive `Arena` as `&'arena self`, i.e. their `self` type is `&'arena Arena<'arena>`
 - `Entry` should almost always be passed around as `&'entry Entry<'entry>` (it's useful to make an alias for this)

That's basically it from the lifetime side, the rest is all in figuring what API you want and implementing the backing storage. 

My crate [`elsa`] implements an arena in 100% safe code [in one of its examples][mutable_arena]. This arena does _not_ save on allocations since [`elsa::FrozenVec`] requires its contents be behind some indirection, and it's not generic, but it's a reasonable way to illustrate how the lifetimes work without getting into the weeds of `unsafe`.

 [`elsa`]: https://docs.rs/elsa
 [`elsa::FrozenVec`]: https://docs.rs/elsa/1.4.0/elsa/vec/struct.FrozenVec.html
 [mutable_arena]: https://github.com/Manishearth/elsa/blob/d23795f144a598d10bb21d8598cef4ed3d087522/examples/mutable_arena.rs