---
layout: post
title: "Container types in Rust: Choosing your guarantees"
date: 2015-05-23 20:29:59 +0530
comments: true
categories: [Rust, Mozilla, Programming]
---

In my [previous post][post-prev] I talked a bit about why the RWlock pattern is important for
accessing data, which is why Rust enforces this pattern either at compile time or runtime
depending on the abstractions used.

It occurred to me that there are many such abstractions in Rust, each with their unique guarantees.
The programmer once again has the choice between runtime and compile time enforcement. It occurred
to me that this plethora of "container types"[^1] could be daunting to newcomers; in this post I intend
to give a thorough explanation of what they do and when they should be used.

I'm assuming the reader knows about [ownership][ownership] and [borrowing][borrowing] in Rust.
Nevertheless, I will attempt to keep the majority of this post accessible to those not yet familiar with these
concepts. Aside from the two links into the book above, [these][skylight-own] [two][arthur-borrow] blog posts cover
the topic in depth.

[post-prev]: http://manishearth.github.io/blog/2015/05/17/the-problem-with-shared-mutability/
[ownership]: http://doc.rust-lang.org/book/ownership.html
[borrowing]: http://doc.rust-lang.org/book/references-and-borrowing.html
[skylight-own]: http://blog.skylight.io/rust-means-never-having-to-close-a-socket/
[arthur-borrow]: http://arthurtw.github.io/2014/11/30/rust-borrow-lifetimes.html

[^1]: I'm not sure if this is the technical term for them, but I'll be calling them that throughout this post.

# Basic pointer types

## `Box<T>`

`Box<T>` is an "owned pointer". While it can hand out borrowed references to the data, it is the only
owner of the data. In particular, when something like the following occurs:

```rust
let x = Box::new(1);
let y = x;
// x no longer accessible here
```

Here, the box was _moved_ into `y`. As `x` no longer owns it,
the compiler will no longer allow the programmer to use `x` after this.

This abstraction is a low cost abstraction for dynamic allocation. If you want
to allocate some memory on the heap and safely pass a pointer to that memory around, this
is ideal. Note that you will only be allowed to share borrowed references to this by
the regular borrowing rules, checked at compile time.



#### Interlude: `Copy`

Move semantics are not special to `Box<T>`; it is a feature of all types which are not `Copy`.

A `Copy` type is one where all the data it logically encompasses (usually, owns) is part of its stack
representation (so a `memcpy` is enough to copy the data).
Most types containing pointers to other data are not `Copy`, since there is additional data
elsewhere, and simply copying the stack representation.

Types like `Vec<T>` and `String` which also have data on the heap are also not `Copy`. Types
like the integer/boolean types are `Copy`

`&T` and raw pointers _are_ `Copy`. Even though they do point
to further data, they do not "own" that data. Whereas `Box<T>` can be thought of as
"some data which happens to be dynamically allocated", `&T` is thought of as "a borrowing reference
to some data". Even though both are pointers, only the first is considered to be "data". Hence,
a copy of the first should involve a copy of the data (which is not part of its stack representation),
but a copy of the second only needs a copy of the reference.

Practically speaking, a type can be `Copy` if a copy of its stack representation doesn't violate
memory safety.

## `&T` and `&mut T`

These are immutable and mutable references respectively. They follow the "read-write lock" pattern
described in my [previous post][post-prev], such that one may either have only one mutable reference
to some data, or any number of immutable ones, but not both. This guarantee is enforced at compile time,
and has no visible cost at runtime. In most cases such pointers suffice for sharing cheap references between
sections of code.

These pointers cannot be copied in such a way that they outlive the lifetime associated with them.

## `*const T` and `*mut T`

These are C-like raw pointers with no lifetime or ownership attached to them. They just point to some location
in memory with no other restrictions. The only guarantee that these provide is that they cannot be dereferenced
except in code marked `unsafe`.

These are useful when building safe, low cost abstractions like `Vec<T>`, but should be avoided in safe code.

## `Rc<T>`

This is the first container we will cover that has a runtime cost.


[`Rc<T>`][rc] is a reference counted pointer. In other words, this lets us have multiple "owning" pointers
to the same data, and the data will be freed (destructors will be run) when all pointers are out of scope.

Internally, it contains a shared "reference count", which is incremented each time the `Rc` is cloned, and decremented
each time one of the `Rc`s goes out of scope. The main responsibility of `Rc<T>` is to ensure that destructors are called
for shared data.

The internal data here is immutable, and if a cycle of references is created, the data will be leaked. If we want
data that doesn't leak when there are cycles, we need a _garbage collector_. I do not know of any existing GCs in Rust,
but [I am working on one with Michael Layzell][gc].


This should be used when you wish to dynamically allocate and share some data (read-only) between various portions
of your program, where it is not certain which portion will finish using the pointer last. It's a viable alternative
to `&T` when `&T` is either impossible to statically check for correctness, or creates extremely unergonomic code where
the programmer does not wish to spend the development cost of working with.

This pointer is _not_ thread safe, and Rust will not let it be sent or shared with other threads. This lets
one avoid the cost of atomics in situations where they are unnecessary.

[rc]: http://doc.rust-lang.org/std/rc/struct.Rc.html
[gc]: http://github.com/Manishearth/rust-gc

# Cell types

"Cells" provide interior mutability. In other words, they contain data which can be manipulated even
if the type cannot be obtained in a mutable form (for example, when it is behind an `&`-ptr or `Rc<T>`).

[The documentation for the `cell` module has a pretty good explanation for these][cell].

In general, they 


[cell-mod]: http://doc.rust-lang.org/doc/std/cell/