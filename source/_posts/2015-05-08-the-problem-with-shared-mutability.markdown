---
layout: post
title: "The problem with single-threaded shared mutability"
date: 2015-05-08 16:56:59 +0530
comments: true
categories: 
---

This is a post that I've been meaning to write for a while now; and the impending release of Rust 1.0 gives
me the perfect impetus to go ahead and do it.

Whilst this post discusses a choice made in the design of Rust; and uses examples in Rust; the principles discussed
here apply to other languages to the most part. I'll also try to make the post easy to understand for those without
a Rust background; please let me know if some code or terminology needs to be explained.


Okay, let's get to it. What I'm going to discuss here is the choice made in Rust to disallow having multiple mutable aliases
to the same data (or a mutable alias when there are active immutable aliases),
**even from the same thread**. In essence, it disallows one from doing things like:


```rust
let mut x = Vec::new();
{
    let ptr = &mut x; // Take a mutable reference to `x`
    ptr.push(1); // Allowed
    let y = x[0]; // Not allowed (will not compile): as long as `ptr` is active,
                  // x cannot be read from ...
    x.push(1);    // .. or written to
}


// alternatively,

let mut x = Vec::new();
x.push(1); // Allowed
{
    let ptr = &x; // Create an immutable reference
    let y = ptr[0]; // Allowed, nobody can mutate
    let y = x[0]; // Similarly allowed
    x.push(1); // Not allowed (will not compile): as long as `ptr` is active,
               // `x` is frozen for mutation
}

```

This is essentially the "Read-Write lock" (RWLock) pattern, except it's not being used in a
threaded context, and the "locks" are done via static analysis (compile time "borrow checking").


Newcomers to the language have the recurring question as to why this exists. [Ownership semantics][book-ownership]
and immutable [borrows][book-borrow] can be grasped because there are concrete examples from languages like C++ of
problems that these concepts prevent. It makes sense that having only one "owner" and then multiple "borrowers" who
are statically guaranteed to not stick around longer than the owner will prevent things like use-after-free.

But what could possibly be wrong with having multiple handles for mutating an object? Why do we need an RWLock pattern? [^0]



[book-ownership]: http://doc.rust-lang.org/nightly/book/ownership.html
[book-borrow]: http://doc.rust-lang.org/nightly/book/references-and-borrowing.html
[^0]: Hereafter referred to as "The Question"

## It causes memory unsafety

This issue is specific to Rust, and I promise that this will be the only Rust-specific answer.


[Rust enums][book-enums] provide a form of algebraic data types. A Rust enum is allowed to "contain" data,
for example you can have the enum

```rust
enum StringOrInt {
    Str(String),
    Int(i64)
}
```

which gives us a type that can either be a variant `Str`, with an associated string, or a variant `Int`[^1], with an associated integer.


With such an enum, we could cause a segfault like so:

```rust
let x = Str("Hi!".to_string()); // Create an instance of the `Str` variant with associated string "Hi!"
let y = &mut x; // Create a mutable alias to x

if let Str(ref insides) = x { // If x is a `Str`, assign its inner data to the variable `insides`
    *y = Int(1); // Set `*y` to `Int(1), therefore setting `x` to `Int(1)` too
    println!("x says: {}", insides); // Uh oh!
}
```

Here, we invalidated the `insides` reference because setting `x` to `Int(1)` meant that there is no longer a string inside it.
However, `insides` is still a reference to a `String`, and the generated assembly would try to dereference the memory location where
the pointer to the allocated string _was_, and probably end up trying to dereference `1` or some nearby data instead, and cause a segfault.

Okay, so far so good. We know that for Rust-style enums to work safely in Rust, we need the RWLock pattern. But can we get more? Not many
languages have such enums, so this shouldn't really be a problem for them.

[book-enums]: http://doc.rust-lang.org/nightly/book/enums.html
[^1]: Note: `Str` and `Null` are variant names which I chose; they are not keywords. Additionally, I'm using "associated foo" loosely here; Rust *does* have a distinct concept of "associated data" but it's not relevant to this post.


## Iterator invalidation

Ah, the example that is brought up almost every time the question above is asked. While I've been quite guilty of
using this example often myself (and feel that it is a very appropriate example that can be quickly explained),
I also find it to be a bit of a cop-out, for reasons which I will explain below. This is partly why I'm writing
this post in the first place; a better idea of the answer to The Question should be available for those who want
to dig deeper.

Iterator invalidation involves using tools like iterators whilst modifying the underlying dataset somehow.

For example,


```rust

let buf = vec![1,2,3,4];

for i in &buf {
    buf.push(i);
}
```

Firstly, this will loop infinitely (if it compiled, which it doesn't, because Rust prevents this). The
equivalent C++ example would be [this one][stackoverflow-iter], which I [use][slides-iter] at every opportunity.

What's happening in both code snippets is that the iterator is really just a pointer to the vector and an index.
It doesn't contain a snapshot of the original vector; so pushing to the original vector will make the iterator iterate for
longer. Pushing once per iteration will obviously make it iterate forever.

The infinite loop isn't even the real problem here. The real problem is that after a while, we could get a segmentation fault.
Internally, vectors have a certain amount of allocated space to work with. If the vector is grown past this space,
a new, larger allocation may need to be done (freeing the old one), since vectors must use contiguous memory.

This means that when the vector overflows its capacity, it will reallocate, invalidating the reference stored in the
iterator, and causing use-after-free.

Of course, there is a trivial solution in this case &mdash; store a reference to the `Vec`/`vector` object inside
the iterator instead of just the pointer to the vector on the heap. This leads to some extra indrection or a larger
stack size for the iterator (depending on how you implement it), but overall will prevent the memory unsafety.


This would still cause problems with more comple situations involving multidimensional vectors, however.




[stackoverflow-iter]: http://stackoverflow.com/questions/5638323/modifying-a-data-structure-while-iterating-over-it
[slides-iter]: http://manishearth.github.io/Presentations/Rust/#/1/2


## "It's effectively threaded"

> Aliasing with mutability in a sufficiently complex, single-threaded program is effectively the same thing as
> accessing data shared across multiple threads without a lock

(The above is my paraphrasing of someone else's quote; but I can't find the original or remember who made it)

Let's step back a bit and figure out why we need locks in multithreaded programs. The way caches and memory work;
we'll never need to worry about two processes writing to the same memory location simultaneously and coming up with
a hybrid value, or a read happening halfway through a write.

What we do need to worry about is the rug being pulled out underneath our feet. A bunch of related reads/writes
would have been written with some invariants in mind, and arbitrary reads/writes possibly happening between them
would invalidate those invariants. For example, a bit of code might first read the length of a vector, and then go ahead
and iterate through it with a regular for loop bounded on the length.
The invariant assumed here is the length of the vector. If `pop()` was called on the vector in some other thread, this invariant could be
invalidated after the read to `length` but before the reads elsewhere, possibly causing a segfault or use-after-free in the last iteration.

However, we can have a situation similar to this (in spirit) in single threaded code. Consider the following:


```rust
let x = some_big_thing();
let len = x.some_vec.len();
for i in 0..len {
    x.do_something_complicated(x.some_vec[i]);
}
```

We have the same invariant here; but can we be sure that `x.do_something_complicated()` doesn't modify `x.some_vec` for
some reason? In a complicated codebase, where `do_something_complicated()` itself calls a lot of other functions which may
also modify `x`, this can be hard to audit.

Of course, the above example is a simplification and contrived; but it doesn't seem unreasonable to assume that such
bugs can happen in large codebases &mdash; where many methods being called have side effects which may not always be evident.

Which means that in large codebases we have almost the same problem as threaded ones. It's very hard to maintain invariants
when one is not completely sure of what each line of code is doing. It's possible to become sure of this by reading through the code
(which takes a while), but further modifications may also have to do the same. It's impractical to do this all the time and eventually
bugs will start cropping up.


On the other hand, having a static guarantee that this can't happen is great. And when the code is too convoluted for
a static guarantee (or you just want to avoid the borrow checker), a single-threaded RWlock-esque type called [RefCell][refcell]
is available in rust. (It provides internal mutability, but in this context one can consider it to be a dynamically checked
version of the borrow checker)

This sort of bug is a good source of reentrancy problems too.

[refcell]: https://doc.rust-lang.org/core/cell/struct.RefCell.html

## Shared mutability is hard to reason about

