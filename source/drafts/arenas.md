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

I'm mostly writing this to talk about the cool lifetime effects, but I figured it's worth writing a general introduction that has something for all Rustaceans.

# What's an arena?

An arena is essentially a way to group up allocations that are expected to have the same lifetime. Quite often you need to allocate a bunch of objects for the lifetime of an event, after which they can all be thrown away wholesale. It's inefficient to call into the system allocator each time, and far more preferable to _preallocate_ a bunch of memory for your objects, cleaning it all up at once once you're done with them as a whole.

Broadly speaking, there are two reasons you might wish to use an arena:

Firstly, your primary goal may be to reduce allocation pressure, as mentioned above. For example, in a game or application, there may be large mishmash of per-frame-tick objects that need to get allocated each frame, and then thrown away. This is _extremely_ common in game development in particular, and allocator pressure is something gamedevs tend to care about. It's easy enough to allocate an arena, fill it up during each frame and clear it out once the frame is over. This has additional benefits of cache locality; you can ensure that most of the per-frame objects (which are likely used more often than other objects) are usually in cache during the frame, since they've been allocated adjacently.

Another goal might be that you want to write self referential data, like a complex graph with cycles, that can get cleaned up all at once. For example, when writing compilers, type information will likely need to reference other types and other such data, leading to a complex, potentially cyclic graph of types. Once you've computed a type you probably don't need to throw it away individually, so you can use an arena to store all your computed type information, cleaning the whole thing up at once when you're at a stage where the types don't matter anymore. Using this pattern allows your code to not have to worry about whether the self-referential bits get deallocated "early", it lets you make the assumption that if you have a `Ty` it lives as long as all the other `Ty`s and can reference them directly.

These two goals are not necessarily disjoint: You may wish to use an arena to achieve both goals simultaneously. But you can also just have an arena that disallows self referential types (but has other nice properties). Later in this post I'm going to implement an arena that allows self-referential types but is not great on allocation pressure, mostly for ease of implementation. _Typically_ if you're writing an arena for self-referential types you can make it simultaneously reduce allocator pressure, but there can be tradeoffs.

# How can I use an arena in Rust?

Typically to _use_ an arena you can just pull in a crate that implements the right kind of arena. There are two that I know of, though [a cursory search of "arena" on crates.io][crates-search] turns up some promising candidates.

## Bumpalo

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