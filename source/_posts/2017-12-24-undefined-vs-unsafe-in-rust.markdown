---
layout: post
title: "Undefined vs Unsafe in Rust"
date: 2017-12-24 13:44:27 +0530
comments: true
categories: rust programming mozilla
---

Recently Julia Evans wrote an [excellent post][b0rk-post] about debugging a segfault in Rust. (Go read it, it's good)

One thing it mentioned was

> I think “undefined” and “unsafe” are considered to be synonyms.

This is ... incorrect. However, we in the Rust community have never really explicitly outlined the
distinction, so that confusion is on us! This blog post is an attempt to clarify the difference of
terminology as used within the Rust community. It's a very useful but subtle distinction and I feel we'd be
able to talk about safety more expressively if this was well known.


 [b0rk-post]: https://jvns.ca/blog/2017/12/23/segfault-debugging/

## Unsafe means two things in Rust, yay

So, first off, the waters are a bit muddied by the fact that Rust uses `unsafe` to both mean "within
an `unsafe {}` block" block and "something Bad is happening here". It's possible to have safe code
within an `unsafe` block; indeed this is the _primary function_ of an `unsafe` block. Somewhat
counterintutively, the `unsafe` block's purpose is to actually tell the compiler "I know you don't
like this code but trust me, it's safe!" (where "safe" is the negation of the _second_ meaning of "unsafe",
i.e. "something Bad is not happening here").

Similarly, we use "safe code" to mean "code not using `unsafe{}` blocks" but also "code that is not unsafe",
i.e. "code where nothing bad happens".

This blog post is primarily about the "something bad is happening here" meaning of "unsafe". When referring
to the other kind I'll specifically say "code within `unsafe` blocks" or something like that.


## Undefined behavior

In languages like C, C++, and Rust, undefined behavior is when you reach a point where
the compiler is allowed to do anything with your code. This is distinct from implementation-defined
behavior, where usually a given compiler/library will do a deterministic thing, however they have some
freedom from the spec in deciding what that thing is.

Undefined behavior can be pretty scary. This is usually because in practice it causes problems when
the compiler assumes "X won't happen because it is undefined behavior", and X ends up happening,
breaking the assumptions. In some cases this does nothing dangerous, but often the compiler will
end up doing wacky things to your code. Dereferencing a null pointer will _sometimes_ cause segfaults
(which is the compiler generating code that actually dereferences the pointer, making the kernel
complain), but sometimes it will be optimized in a way that assumes it won't and moves around code
such that you have major problems.

Undefined behavior is a global property, based on how your code is _used_. The following function
in C++ or Rust may or may not exhibit undefined behavior, based on how it gets used:

```cpp
int deref(int* x) {
    return *x;
}
```

```rust
// do not try this at home
fn deref(x: *mut u32) -> u32 {
    unsafe { *x }
}
```

As long as you always call it with a valid pointer to an integer, there is no undefined behavior
involved.

But in either language, if you use it with some pointer conjured out of thin air (or, like `0x01`), that's
probably undefined behavior.

As it stands, UB is a property of the entire program and its execution. Sometimes you may have snippets of code
that will always exhibit undefined behavior regardless of how they are called, but in general UB
is a global property.


## Unsafe behavior

Rust's concept of "unsafe behavior" (I'm coining this term because "unsafety" and "unsafe code" can
be a bit confusing) is far more scoped. Here, `fn deref` _is_ "unsafe"[^1], even if you _always_
call it with a valid pointer. The reason it is still unsafe is because it's possible to trigger UB by only
changing the "safe" caller code. I.e. "changes to code outside unsafe blocks can trigger UB if they include
calls to this function".

Basically, in Rust a bit of code is "safe" if it cannot exhibit undefined behavior under all circumstances of
that code being used. The following code exhibits "safe behavior":

```rust
unsafe {
    let x = 1;
    let raw = &x as *const u32;
    println!("{}", *raw);
}
```

We dereferenced a raw pointer, but we knew it was valid. Of course, actual `unsafe` blocks will
usually be "actually totally safe" for less obvious reasons, and part of this is because
[`unsafe` blocks pollute the entire module][nomicon-module].

 [^1]: Once again in we have a slight difference between an "`unsafe fn`", i.e. a function that needs an `unsafe` block to call and probably is unsafe, and an "unsafe function", a function that exhibits unsafe behavior.
 [nomicon-module]: https://doc.rust-lang.org/nomicon/working-with-unsafe.html#working-with-unsafe

Basically, "safe" in Rust is a more local property. Code isn't safe just because you only use it in
a way that doesn't trigger UB, it is safe because there is literally _no way[^2] to use it such that it
will do so_. No way to do so without using `unsafe` blocks, that is[^2].

 [^2]: This caveat and the confusing dual-usage of the term "safe" lead to the rather tautological-sounding sentence "Safe Rust code is Rust code that cannot cause undefined behavior when used in safe Rust code"


This is a distinction that's _possible_ to draw in Rust because it gives us the ability
to compartmentalize safety. Trying to apply this definition to C++ is problematic; you can
ask "is `std::unique_ptr<T>` safe?", but you can _always_ use it within code in a way that you trigger
undefined behavior, because C++ does not have the tools for compartmentalizing safety. The distinction
between "code which doesn't need to worry about safety" and "code which does need to worry about safety"
exists in Rust in the form of "code outside of `unsafe {}`" and "code within `unsafe {}`", whereas in
C++ it's a lot fuzzier and based on expectations (and documentation/the spec).

So C++'s `std::unique_ptr<T>` is "safe" in the sense that it does what you expect but
if you use it in a way counter to how it's _supposed_ to be used (constructing one from an invalid pointer, for example)
it can blow up. This is still a useful sense of safety, and is how one regularly reasons about safety in C++. However it's not
the same sense of the term as used in Rust, which can be a bit more formal about what the expectations
actually are.

So `unsafe` in Rust is a strictly more general concept -- all code exhibiting undefined behavior in Rust is also "unsafe",
however not all "unsafe" code in Rust exhibits undefined behavior as written in the current program.

Rust furthermore attempts to guarantee that you will not trigger undefined behavior if you do not use `unsafe {}` blocks.
This of course depends on the correctness of the compiler (it has bugs) and of the libraries you use (they may also have bugs)
but this compartmentalization gets you most of the way there in having UB-free programs.
