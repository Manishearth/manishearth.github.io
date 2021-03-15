---
layout: post
title: "Arenas in Rust"
date: 2021-03-14 10:00:00 -0800
comments: true
categories: ["programming", "rust", "tidbits"]
---

There's been some discussion about arenas in Rust recently, and I thought I'd write about them.

Arenas aren't something you would typically reach for in Rust so fewer people know about them; you only really see them in applications for various niche use cases. Usually you can use an arena by pulling in a crate and not using additional `unsafe`, so there's no need to be particularly skittish around them in Rust, and it seems like it would be useful knowledge, especially for people coming to Rust fields where arenas are more common.

Furthermore, there's a set of _really cool_ lifetime effects involved when implementing self-referential arenas, that I don't think have been written about before.

I'm mostly writing this to talk about the cool lifetime effects, but I figured it's worth writing a general introduction that has something for all Rustaceans. If you know what arenas are and just want the cool lifetimes you can skip directly to [the section on implementing self-referential arenas][section-3]. Otherwise, read on.

 [section-3]: #implementing-a-self-referential-arena

## What's an arena?

An arena is essentially a way to group up allocations that are expected to have the same lifetime. Sometimes you need to allocate a bunch of objects for the lifetime of an event, after which they can all be thrown away wholesale. It's inefficient to call into the system allocator each time, and far more preferable to _preallocate_ a bunch of memory for your objects, cleaning it all up at once once you're done with them.

Broadly speaking, there are two reasons you might wish to use an arena:

Firstly, your primary goal may be to reduce allocation pressure, as mentioned above. For example, in a game or application, there may be large mishmash of per-frame-tick objects that need to get allocated each frame, and then thrown away. This is _extremely_ common in game development in particular, and allocator pressure is something gamedevs tend to care about. With arenas, it's easy enough to allocate an arena, fill it up during each frame and clear it out once the frame is over. This has additional benefits of cache locality: you can ensure that most of the per-frame objects (which are likely used more often than other objects) are usually in cache during the frame, since they've been allocated adjacently.

Another goal might be that you want to write self referential data, like a complex graph with cycles, that can get cleaned up all at once. For example, when writing compilers, type information will likely need to reference other types and other such data, leading to a complex, potentially cyclic graph of types. Once you've computed a type you probably don't need to throw it away individually, so you can use an arena to store all your computed type information, cleaning the whole thing up at once when you're at a stage where the types don't matter anymore. Using this pattern allows your code to not have to worry about whether the self-referential bits get deallocated "early", it lets you make the assumption that if you have a `Ty` it lives as long as all the other `Ty`s and can reference them directly.

These two goals are not necessarily disjoint: You may wish to use an arena to achieve both goals simultaneously. But you can also just have an arena that disallows self referential types (but has other nice properties). Later in this post I'm going to implement an arena that allows self-referential types but is not great on allocation pressure, mostly for ease of implementation. _Typically_ if you're writing an arena for self-referential types you can make it simultaneously reduce allocator pressure, but there can be tradeoffs.

## How can I use an arena in Rust?

Typically to _use_ an arena you can just pull in a crate that implements the right kind of arena. There are two that I know of that I'll talk about below, though [a cursory search of "arena" on crates.io][crates-search] turns up many other promising candidates.

I'll note that if you just need cyclic graph structures, you don't _have_ to use an arena, the excellent [`petgraph`] crate is often sufficient.

 [`petgraph`]: https://docs.rs/petgraph/

### Bumpalo

[`Bumpalo`] is a fast "bump allocator", which allows heterogenous contents but not cyclic references.

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

Every call to [`Bump::alloc()`] returns a mutable reference to the allocated object. You can allocate different objects, and they can even reference each other[^0]. By default it does not call destructors on its contents; however you can use [`bumpalo::boxed`][bumpalo::boxed] (or custom allocators on Nightly) to get this behavior. You can similarly use [`bumpalo::collections`][bumpalo::collections] to get [`bumpalo`]-backed vectors and strings.

Rust does support swapping out the global allocator used by `Box`, `Vec`, `HashMap`, etc using [`#![global_allocator]`][global-alloc]; and [`bumpalo`] supports being used in this way, so this crate is also useful for environments where you just need a fast bump allocator (e.g. light allocation in WASM).

 [crates-search]: https://crates.io/search?q=arena
 [`bumpalo`]: https://docs.rs/bumpalo
 [bumpalo::boxed]: https://docs.rs/bumpalo/3.6.1/bumpalo/boxed/index.html
 [bumpalo::collections]: https://docs.rs/bumpalo/3.6.1/bumpalo/collections/index.html
 [`Bump::alloc()`]: https://docs.rs/bumpalo/3.6.1/bumpalo/struct.Bump.html#method.alloc
 [^0]: But not in a cyclic way; the borrow checker will enforce this!
 [global-alloc]: https://doc.rust-lang.org/std/alloc/index.html#the-global_allocator-attribute

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

Unlike [`bumpalo`], [`typed-arena`] will always run destructors on its contents when the arena itself goes out of scope[^1].


 [`typed-arena`]: https://docs.rs/typed-arena/
 [^1]: You may wonder how it is safe for destructors to be safely run on cyclic references -- after all, the destructor of whichever entry gets destroyed second will be able to read a dangling reference. We'll cover this later in the post but it has to do with drop check, and specifically that if you attempt to set up cycles, the only explicit destructors allowed on the arena entries themselves will be ones on appropriately marked types.

## Implementing a self-referential arena

Self referential arenas are interesting because, typically, Rust is very very wary of self-referential data. But arenas let you clearly separate the step of "I don't care about this object" and "this object can be deleted" in a way that is sufficient to allow self-referential and cyclic types.

It's pretty rare to need to implement your own arena -- [`bumpalo`] and [`typed-arena`] cover most of the use cases, and if they don't cover yours you probably can find something that does on [crates.io][crates-search]. But if you really need to, or if you're interested in the nitty-gritty lifetime details, this section is for you.

{% aside %}
For people less familiar with lifetimes: the lifetimes in the syntaxes `&'a Foo` and `Foo<'b>` mean different things. `'a` in `&'a Foo` is the lifetime _of_ `Foo`, or, at least the lifetime of _this_ reference to `Foo`. `'b` in `Foo<'b>` is a lifetime _parameter_ of `Foo`, and typically means something like "the lifetime of data `Foo` is allowed to reference".{% endaside %}


The key to implementing an arena `Arena` with entries typed as `Entry` is in the following rules:

 - `Arena` and `Entry` should both have a lifetime parameter: `Arena<'arena>` and `Entry<'arena>`
 - `Arena` methods should all receive `Arena<'arena>` as `&'arena self`, i.e. their `self` type is `&'arena Arena<'arena>`
 - `Entry` should almost always be passed around as `&'arena Entry<'arena>` (it's useful to make an alias for this)
 - Use interior mutability; `&mut self` on `Arena` will make everything stop compiling. If using `unsafe` for mutability, make sure you have a `PhantomData` for `RefCell<Entry<'arena>>` somewhere.

That's basically it from the lifetime side, the rest is all in figuring what API you want and implementing the backing storage. Armed with the above rules you should be able to make your custom arena work with the guarantees you need without having to understand what's going on with the underlying lifetimes.

Let's go through an implementation example, and then dissect _why_ it works.

### Implementation

My crate [`elsa`] implements an arena in 100% safe code [in one of its examples][mutable_arena]. This arena does _not_ save on allocations since [`elsa::FrozenVec`] requires its contents be behind some indirection, and it's not generic, but it's a reasonable way to illustrate how the lifetimes work without getting into the weeds of implementing a _really good_ arena with `unsafe`.

The example implements an arena of `Person<'arena>` types, `Arena<'arena>`. The goal is to implement some kind of directed social graph, which may have cycles.

```rust
use elsa::FrozenVec;

struct Arena<'arena> {
    people: FrozenVec<Box<Person<'arena>>>,
}
```

[`elsa::FrozenVec`] is an append-only `Vec`-like abstraction that allows you to call `.push()` without needing a mutable reference, and is how we'll be able to implement this arena in safe code.

Each `Person<'arena>` has a list of people they follow but also keeps track of people who follow them:

```rust
struct Person<'arena> {
    pub follows: FrozenVec<PersonRef<'arena>>,
    pub reverse_follows: FrozenVec<PersonRef<'arena>>,
    pub name: &'static str,
}

// following the rule above about references to entry types
type PersonRef<'arena> = &'arena Person<'arena>;
```

The lifetime `'arena` is essentially "the lifetime of the arena itself". This is where it starts getting weird: typically if your type has a lifetime _parameter_, the caller gets to pick what goes in there. You don't get to just say "this is the lifetime of the object itself", the caller would typically be able to instantiate an `Arena<'static>` if they wish, or an `Arena<'a>` for some `'a`. But here we're declaring that `'arena` is the lifetime of the arena itself; clearly something fishy is happening here.

Here's where we actually implement the arena:

```rust
impl<'arena> Arena<'arena> {
    fn new() -> Arena<'arena> {
        Arena {
            people: FrozenVec::new(),
        }
    }
    
    fn add_person(&'arena self, name: &'static str,
                  follows: Vec<PersonRef<'arena>>) -> PersonRef<'arena> {
        let idx = self.people.len();
        self.people.push(Box::new(Person {
            name,
            follows: follows.into(),
            reverse_follows: Default::default(),
        }));
        let me = &self.people[idx];
        for friend in &me.follows {
            // We're mutating existing arena entries to add references,
            // potentially creating cycles!
            friend.reverse_follows.push(me)
        }
        me
    }

    fn dump(&'arena self) {
        // code to print out every Person, their followers, and the people who follow them
    }
}
```

Note the `&'arena self` in `add_person`.

A _good_ implementation here would typically separate out code handling the higher level invariant of "if A `follows` B then B `reverse_follows` A", but this is just an example.

And finally, we can use the arena like this:

```rust
fn main() {
    let arena = Arena::new();
    let lonely = arena.add_person("lonely", vec![]);
    let best_friend = arena.add_person("best friend", vec![lonely]);
    let threes_a_crowd = arena.add_person("threes a crowd", vec![lonely, best_friend]);
    let rando = arena.add_person("rando", vec![]);
    let _everyone = arena.add_person("follows everyone", vec![rando, threes_a_crowd, lonely, best_friend]);
    arena.dump();
}
```

In this case all of the "mutability" happens in the implementation of the arena itself, but it would be possible for this code to add entries directly to the `follows`/`reverse_follows` lists, or `Person` could have `RefCell`s for other kinds of links, or whatever.

 [`elsa`]: https://docs.rs/elsa
 [`elsa::FrozenVec`]: https://docs.rs/elsa/1.4.0/elsa/vec/struct.FrozenVec.html
 [mutable_arena]: https://github.com/Manishearth/elsa/blob/915d26008d8bae069927c551da506dba05d2755b/examples/mutable_arena.rs

### How the lifetimes work

So how does this work? As I said earlier, with such abstractions in Rust, the caller typically has freedom to set the lifetime based on what they do with it. For example, if you have a `HashMap<K, &'a str>`, the `'a` will get set based on the lifetime of what you try to insert.

When you construct the `Arena` its lifetime parameter is indeed still unconstrained, and we can test this by checking that the following code, which forcibly constrains the lifetime, still compiles.

```rust
let arena: Arena<'static> = Arena::new();
```

But the moment you try to do anything with the arena, this stops working:

```rust
let arena: Arena<'static> = Arena::new();
let lonely = arena.add_person("lonely", vec![]);
```

```text
error[E0597]: `arena` does not live long enough
  --> examples/mutable_arena.rs:5:18
   |
4  |     let arena: Arena<'static> = Arena::new();
   |                -------------- type annotation requires that `arena` is borrowed for `'static`
5  |     let lonely = arena.add_person("lonely", vec![]);
   |                  ^^^^^ borrowed value does not live long enough
...
11 | }
   | - `arena` dropped here while still borrowed
```

The `add_person` method is somehow suddenly forcing the `'arena` parameter of `Arena` to be set to its _own_ lifetime, constraining it (and making it impossible to force-constrain it to be anything else with type annotations).

What's going on here is a neat interaction with the `&'arena self` signature of `add_person` (i.e. `self` is `&'arena Arena<'self>`), and the fact that `'arena` in `Arena<'arena>` is an [_invariant lifetime_][variance].

Usually in your Rust programs, lifetimes are a little bit stretchy-squeezy. The following code compiles just fine:

```rust
// ask for two strings *with the same lifetime*
fn take_strings<'a>(x: &'a str, y: &'a str) {}

// string literal with lifetime 'static
let lives_forever = "foo";
// owned string with shorter, local lifetime
let short_lived = String::from("bar");

// still works!
take_strings(lives_forever, &*short_lived);
```

In this code, Rust is happy to notice that while `lives_forever` and `&*short_lived` have different lifetimes, it's totally acceptable to _pretend_ `lives_forever` has a shorter lifetime for the duration of the `take_strings` function. It's just a reference, a reference valid for a long lifetime is _also_ valid for a shorter lifetime.

The thing is, this stretchy-squeeziness is not the same for all lifetimes! The [nomicon chapter on subtyping and variance][nomicon-subtyping] goes into detail on _why_ this is the case, but a general rule of thumb is that most lifetimes are "squeezy"[^2] like the one in `&'a str` above, but if some form of mutability is involved, they are rigid, also known as "invariant". You can also have "stretchy"[^3] lifetimes if you're using function types, but they're rare.

Our `Arena<'arena>` is using interior mutability (via the `FrozenVec`) in a way that makes `'arena` invariant.


Let's look at our two lines of code again. When the compiler sees the first line of the code below, it constructs `arena`, whose lifetime we'll call `'a`. At this point the type of `arena` is `Arena<'?>`, where `'?` is made up notation for a yet-unconstrained lifetime.

```rust
let arena = Arena::new(); 
let lonely = arena.add_person("lonely", vec![]);
```

Let's actually rewrite this to be clearer on what the lifetimes are.

```rust
let arena = Arena::new(); // type Arena<'?>, lives for 'a

// explicitly write the `self` that gets constructed when you call add_person
let ref_to_arena = &arena; // type &'a Arena<'?>
let lonely = Arena::add_person(ref_to_arena, "lonely", vec![]);

```

Remember the second rule I listed earlier?

> `Arena` methods should all receive `Arena<'arena>` as `&'arena self`, i.e. their `self` type is `&'arena Arena<'arena>`

We followed this rule; the signature of `add_person` is `fn add_person(&'arena self)`. This means that `ref_to_arena` is _forced_ to have a lifetime that matches the pattern `&'arena Arena<'arena>`. Currently its lifetime is `&'a Arena<'?>`, which means that `'?` is _forced_ to be the same as `'a`, i.e. the lifetime of the `arena` variable itself. If the lifetime weren't invariant, the compiler would be able to squeeze other lifetimes to fit, but it is invariant, and the unconstrained lifetime is forced to be exactly one lifetime.

And by this rather subtle sleight of hand we're able to force the compiler to set the lifetime _parameter_ of `Arena<'arena>` to the lifetime of its _instance_.

After this, the rest is pretty straightforward. `Arena<'arena>` holds entries of type `Person<'arena>`, which is basically a way of saying "a `Person` that is allowed to reference items of lifetime `'arena`, i.e. items in `Arena`". `type PersonRef<'arena> = &'arena Person<'arena>` is a convenient shorthand for "a reference to a `Person` that lives in `Arena` and is allowed to reference objects from it".


 [variance]: https://doc.rust-lang.org/nomicon/subtyping.html#variance
 [nomicon-subtyping]: https://doc.rust-lang.org/nomicon/subtyping.html
 [^2]: The technical term for this is "covariant lifetime"
 [^3]: The technical term for this is "contravariant lifetime"

### What about destructors?

So a thing I've not covered so far is how this can be safe in the presence of destructors. If your arena is allowed to have cyclic references, and you write a destructor reading from those cyclic references, whichever participant in the cycle that is deleted later on will have dangling references.

This gets to a _really_ obscure part of Rust, even more obscure than variance. You almost never need to really understand this, beyond "explicit destructors subtly change borrow check behavior". But it's useful to know to get a better mental model of what's going on here.

If we add the following code to our arena example:

```rust
impl<'arena> Drop for Person<'arena> {
    fn drop(&mut self) {
        println!("goodbye {:?}", self.name);
        for friend in &self.reverse_follows {
            // potentially dangling!
            println!("\t\t{}", friend.name);
        }
    }
}
```

we actually get this error:

```rust
error[E0597]: `arena` does not live long enough
  --> examples/mutable_arena.rs:5:18
   |
5  |     let lonely = arena.add_person("lonely", vec![]);
   |                  ^^^^^ borrowed value does not live long enough
...
11 | }
   | -
   | |
   | `arena` dropped here while still borrowed
   | borrow might be used here, when `arena` is dropped and runs the destructor for type `Arena<'_>`
```

The presence of destructors subtly changes the behavior of the borrow checker around self-referential lifetimes. The exact rules are tricky and [explained in the nomicon][dropck], but _essentially_ what happened was that the existence of a custom destructor on `Person<'arena>` made `'arena` in `Person` (and thus `Arena`) a lifetime which is "observed during destruction". This is then taken into account during borrow checking -- suddenly the implicit `drop()` at the end of the scope is known to be able to read `'arena` data, and Rust makes the appropriate conclusion that `drop()` will be able to read things after they've been cleaned up, since destruction is itself a mutable operation, and `drop()` is run interspersed in it.

Of course, a reasonable question to ask is how we can store things like `Box` and `FrozenVec` in this arena if destructors aren't allowed to "wrap" types with `'arena`. The reason is that Rust knows that `Drop` on `Box` _cannot_ inspect `person.follows` because `Box` does not even know what `Person` is, and has promised to never try and find out. This wouldn't necessarily be true if we had a random generic type since the destructor can call trait methods (or specialized blanket methods) which _do_ know how to read the contents of `Person`, but in such a case the subtly changed borrow checker rules would kick in again. The stdlib types and other custom datastructures achieve this with an escape hatch, [`#[may_dangle]`][may_dangle] (also known as "the eyepatch"[^4]), which allows you to pinky swear that you won't be reading from a lifetime or generic parameter in a custom destructor.

This applies to crates like [`typed-arena`] as well; if you are creating cycles you will not be able to write custom destructors on the types you put in the arena. You _can_ write custom destructors with [`typed-arena`] as long as you refrain from mutating things in ways that can create cycles; so you will not be able to use interior mutability to have one arena entry point to another.

 [dropck]: https://doc.rust-lang.org/nomicon/dropck.html
 [may_dangle]: https://doc.rust-lang.org/nomicon/dropck.html#an-escape-hatch
 [^4]: Because you're claiming the destructor "can't see" the type or lifetime, see?

_Thanks to [Mark Cohen](https://mpc.sh) and [Nika Layzell](https://twitter.com/kneecaw/) for reviewing drafts of this post._