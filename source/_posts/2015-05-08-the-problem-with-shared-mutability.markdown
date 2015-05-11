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

 