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

[The documentation for the `cell` module has a pretty good explanation for these][cell-mod].

These types are _generally_ found in struct fields, but they may be found elsewhere too.

## [`Cell<T>`][cell]

`Cell<T>` is a type that provides zero-cost interior mutability, but only for `Copy` types.
Since the compiler knows that all the data owned by the contained value is on the stack, there's
no worry of leaking any data behind references (or worse!) by simply replacing the data.

It is still possible to violate your own invariants using this container, so be careful when
using it. If a field is wrapped in `Cell`, it's a nice indicator that the chunk of data is mutable
and may not stay the same between the time you first read it and when you intend to use it.

This is useful for mutating primitives and other `Copy` types when there is no easy way of
doing it in line with the static rules of `&` and `&mut`.


```rust
let x = Cell::new(1);
let y = &x;
let z = &x;
x.set(2);
y.set(3);
z.set(4);
println!("{}", x.get());
```

Note that here we were able to mutate the same value from various immutable references.


This has the same runtime cost as the following:


```rust
let mut x = 1;
let y = &mut x;
let z = &mut x;
x = 2;
*y = 3;
*z = 4;
println!("{}", x;
```

but it has the added benefit of actually compiling successfully.


## [`RefCell<T>`][refcell]

`RefCell<T>` also provides interior mutability, but isn't restricted to `Copy` types.

Instead, it has a runtime cost. `RefCell<T>` enforces the RWLock pattern at runtime (it's like a single-threaded mutex),
unlike `&T`/`&mut T` which do so at compile time. This is done by the `borrow()` and
`borrow_mut()` functions, which modify an internal reference count and return smart pointers
which can be dereferenced immutably and mutably respectively. The refcount is restored
when the smart pointers go out of scope. With this system, we can dynamically ensure that
there are never any other borrows active when a mutable borrow is active. If the programmer
attempts to make such a borrow, the thread will panic.


```rust
let x = RefCell::new(vec![1,2,3,4]);
{
    println!("{:?}", *x.borrow())
}

{
    let ref = x.borrow_mut();
    ref.push(1);
}

```

Similar to `Cell`, this is mainly useful for situations where it's hard or impossible to satisfy the
borrow checker. Generally one knows that such mutations won't happen in a nested form, but it's good
to check.

For large, complicated programs, it becomes useful to put some things in `RefCell`s to
make things simpler. For example, a lot of the maps in [the `ctxt` struct][ctxt] in the rust compiler
internals are inside this container. These are only modified once (during creation, which is not
right after initialization) or a couple of times in well-separated places. However, since this struct is
pervasively used everywhere, juggling mutable and immutable pointers would be hard (perhaps impossible)
and probably form a soup of `&`-ptrs which would be hard to extend. On the other hand, the `RefCell`
provides a cheap (not zero-cost) way of safely accessing these. In the future, if someone adds some code
that attempts to modify the cell when it's already borrowed, it will cause a (usually deterministic) panic
which can be traced back to the offending borrow.

Similarly, in Servo's DOM we have a lot of mutation, most of which is local to a DOM type, but
some of which crisscrosses the DOM and modifies various things. Using `RefCell` and `Cell` to guard
all mutation lets us avoid worrying about mutability everywhere, and it simultaneously
highlights the places where mutation is _actually_ happening.

Note that `RefCell` should be avoided if a mostly simple solution is possible with `&` pointers.


[cell-mod]: http://doc.rust-lang.org/doc/std/cell/
[cell]: http://doc.rust-lang.org/doc/std/cell/struct.Cell.html
[refcell]: http://doc.rust-lang.org/doc/std/cell/struct.RefCell.html
[ctxt]: http://doc.rust-lang.org/rustc/middle/ty/struct.ctxt.html

# Synchronous types

Many of the types above cannot be used in a threadsafe manner. Particularly, `Rc<T>` and `RefCell<T>`,
which both use non-atomic ref counts, cannot be used this way. This makes them cheaper to use, but one
needs thread safe versions of these too. They exist, in the form of `Arc<T>` and `Mutex<T>`/`RWLock<T>`

Note that the non-threadsafe types _cannot_ be sent between threads, and this is checked at compile time.
I'll touch on how this is done later in this post.

There are many useful containers for concurrent programming in the [sync][sync] module, but I'm only going to cover
the major ones.

[sync]: https://doc.rust-lang.org/nightly/std/sync/index.html

## [`Arc<T>`][arc]

This is just a version of `Rc<T>` that uses an atomic reference count (hence, "Arc"). This can be sent
freely between threads.


This has the added cost of using atomics for changing the refcount (which will happen whenever it is cloned
or goes out of scope), and it provides the guarantee that the destructor for the internal data
will be run when the last `Arc` goes out of scope (barring any cycles). When sharing data from an `Arc` in
a single thread, it is preferable to share `&` pointers whenever possible.


C++'s `shared_ptr` is similar to `Arc`, however in C++s case the inner data is always mutable. For semantics
similar to that from C++, we should use `Arc<Mutex<T>>`, `Arc<RwLock<T>>`, or `Arc<UnsafeCell<T>>` (`UnsafeCell<T>`
is a cell type that can be used to hold any data and has no runtime cost, but accessing it requires `unsafe` blocks).
The last one should only be used if one is certain that the usage won't cause any memory safety. Remember that
writing to a struct is not an atomic operation, and many functions like `vec.push()` can reallocate internally
and cause unsafe behavior (so even monotonicity may not be enough to justify `UnsafeCell`)

[arc]: https://doc.rust-lang.org/std/sync/struct.Arc.html

## [`Mutex<T>`][mutex] and [`RwLock<T>`][rwlock]

These provide mutual-exclusion via RAII guards. For both of these, the
mutex is opaque until one calls `lock()` on it, at which point the thread will
block until a lock can be acquired, and then a guard will be returned. This guard
can be used to access the inner data (mutably), and the lock will be released when the
guard goes out of scope.


```rust
{
    let guard = mutex.lock();
    // guard dereferences mutably to the inner type
    *guard += 1;
} // lock released when destructor runs
```


`RwLock` has the added benefit of being efficient for multiple reads. It is always
safe to have multiple readers to shared data as long as there are no writers; and `RwLock`
lets readers acquire a "read lock". Such locks can be acquired concurrently and are kept track of
via a reference count. Writers must obtain a "write lock" which can only be obtained when all readers
have gone out of scope.

Both of these provide safe shared mutability across threads, but are costly, similar to `Arc`. There also
is the danger of deadlocks, which Rust does not try to prevent. Some level of protocol safety can be obtained via
the type system, however. An example  of this is [rust-sessions][sessions], an experimental library which uses session
types for protocol safety.



[rwlock]: https://doc.rust-lang.org/std/sync/struct.RwLock.html
[mutex]: https://doc.rust-lang.org/std/sync/struct.Mutex.html
[sessions]: https://github.com/Munksgaard/rust-sessions

# Bonus section: [`Send`][send] and [`Sync`][sync]

See also: [Huon's blog post on the same topic][huon-send]

_In every talk I have given till now, the question "how does Rust achieve thread safety?"
has invariably come up. I usually just give an overview, but here I thought I would be
able to dive a bit deeper since it ties together many things introduced in this post._

Similar to `Copy`, two more "marker" traits exist in the standard library. These
help segregate thread safe data structures from the rest.

These are auto-implemented using a feature called "opt in builtin traits". So,
for example, if struct `Foo` is `Sync`, all structs containing `Foo` will
also be `Sync`, unless we explicitly opt out using `impl !Sync for Bar {}`.

This means that, for example, a `Sender` for a `Send` type is itself `Send`,
but a `Sender` for a non-`Send` type will not be `Send`. This pattern is quite powerful;
it lets one use channels with non-threadsafe data in a single-threaded context without
requiring a separate "single threaded" channel abstraction.

At the same time, structs like `Rc` and `RefCell` which contain `Send`/`Sync` fields
have explicitly opted out of one or more of these because the invariants they rely on do not
hold in threaded situations.


These two have slightly differing meanings, but are very intertwined.

`Send` types can be moved between threads without an issue. Most objects
which completely own their contained data qualify here. Notably, `Rc` doesn't
(since it is shared ownership). Another exception is [LocalKey][localkey], which
_does_ own its data but isn't valid from other threads.

Even though types like `RefCell` use non atomic reference counting, it can be sent safely
between threads because this is a transfer of ownership. Sending a `RefCell` to another thread
will be a move and will make it unusable from the original thread; so this is fine.

`Sync`, on the other hand, is about synchronous access. It answers the question: "if
multiple threads were all trying to access this data, would it be safe?". Types like
`Mutex` and other lock/atomic based types implement this, along with primitive types.
Things containing pointers generally are not `Sync`.

`Sync` is sort of a crutch to `Send`, it helps make other types `Send` when sharing is
involved. For example, `&T` and `Arc<T>` are only `Send` when the inner data is `Sync` (and 
additionally `Send` in the case of `Arc<T>`).

Putting this all together, the gatekeeper for all this is [`thread::spawn()`][spawn]. It has the signature

```rust
pub fn spawn<F, T>(f: F) -> JoinHandle<T> where F: FnOnce() -> T, F: Send + 'static, T: Send + 'static
```

Admittedly, this is confusing, partially because it's allowed to return a value (and it returns a handle from which we can block on a thread join).

We can simplify this:

```rust
pub fn spawn<F>(f: F) where F: FnOnce(), F: Send + 'static
```

which can be called like:

```rust
let mut x = vec![1,2,3,4];

// `move` instructs the closure to move out of its environment
thread::spawn(move || {
   x.push(1);

});

// x is not accessible here

```

In words, `spawn()` will take a callable (usually a closure) that will be called once, and contains
data which is `Send` and `'static`. `'static` just means that there is no borrowed
data contained in the closure.


There is also a way to utilize the `Send`-ness of `&T`, namely [`thread::scoped`][scoped]. This function
does not have the `'static` bound, but it instead has an RAII guard which forces a join before the borrow ends. This
allows for easy fork-join parallelism without necessarily needing a `Mutex`.
Sadly, there [are][peaches] [problems][more-peaches] which crop up when this interacts with `Rc` cycles, so the API
is currently unstable and will be redesigned.

[send]: http://doc.rust-lang.org/std/marker/trait.Send.html
[sync]: http://doc.rust-lang.org/std/marker/trait.Sync.html
[huon-send]: http://huonw.github.io/blog/2015/02/some-notes-on-send-and-sync/
[localkey]: https://doc.rust-lang.org/nightly/std/thread/struct.LocalKey.html
[spawn]: http://doc.rust-lang.org/std/thread/fn.spawn.html
[scoped]: http://doc.rust-lang.org/std/thread/fn.scoped.html
[peaches]: http://cglab.ca/~abeinges/blah/everyone-peaches/
[more-peaches]: http://smallcultfollowing.com/babysteps/blog/2015/04/29/on-reference-counting-and-leaks/