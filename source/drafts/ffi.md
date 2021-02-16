---
layout: post
title: "Integrating Rust and C++ in Firefox"
date: 2021-02-15 12:08:46 -0700
comments: true
categories: [rust, c++, programming]
---

_This post was originally drafted in August 2018, but I never got around to finishing it. As such, parts of its framing (e.g. the focus on bindgen) are outdated, given the relative infancy of the interop space at the time. I was recently told that the post is still useful in this form so I decided to finish and publish it anyway, while attempting to mark outdated things as such when I notice them. Everything after the allocators section was written near the time of publication._

In 2017 I worked on the [Stylo] project, uplifting Servo's CSS engine ("style system") into Firefox's browser engine
("Gecko"). This involved a _lot_ of gnarly FFI between Servo's Rust codebase and Firefox's C++ codebase. There were a
lot of challenges in doing this, and I feel like it's worth sharing things from our experiences.

If you're interested in Rust integrations, you may find [this talk by Katharina on Rust - C++ FFI][rustconf-kookie], and [this blog post by Henri on integrating encoding-rs into Firefox][henri-blog] useful as well.



 [Stylo]: https://hacks.mozilla.org/2017/08/inside-a-super-fast-css-engine-quantum-css-aka-stylo/
 [rustconf-kookie]: https://www.youtube.com/watch?v=x9acx2zgx4Q
 [henri-blog]: https://hsivonen.fi/modern-cpp-in-rust/

## Who is this post for?

So, first off the bat, I'll mention that when integrating Rust into a C++ codebase, you
want to _avoid_ having integrations as tight as Stylo. Don't do what we did; make your Rust
component mostly self-contained so that you just have to maintain something like ten FFI functions
for interacting with it. If this is possible to do, you should do it and your life will be _much_ easier. Pick a clean API boundary, define a straightforward API, use cbindgen or bindgen if necessary without any tricks, and you should be good to go.

That said, sometimes you _have_ to have gnarly integrations, and this blog post is for those use cases.
These techniques mostly use bindgen in their examples, however you can potentially use them with hand-rolled bindings or another tool as well. If you're at this level of complexity, however, the potential for mistakes in the hand-rolled bindings is probably not worth it.

_Note from 2021: [cxx] is probably a better tool for many of the use cases here, though many of the techniques still transfer._

[cxx]: https://github.com/dtolnay/cxx

## What was involved in Stylo's FFI?

So, what made Stylo's FFI so complicated?

It turns out that browsers are quite monolithic. You can split them into vaguely-defined components, but
these components are still tightly integrated. If you intend to replace a component, you may need to
make a jagged edge of an integration surface.

The style system is more self-contained than other parts, but it's still quite tightly integrated.

The main job of a "style system" is to take the CSS rules and DOM tree, and run them through "the cascade"[^1]
with an output of "computed styles" tagged on each node in the tree. So, for example, it will take a document like
the following:

```html
<style type="text/css">
    body {
        font-size: 12px;
    }
    div {
        height: 2em;
    }
</style>
<body>
    <div id=foo></div>

</body>
```

and turn it into something like:

 - `<body>` has a `font-size` of `12px`, everything else is the default
 - the `div` `#foo` has a computed `height` of `24px` [^3], everything else is the default. It "inherits" the `font-size` from `<body>` as `12px`

From a code point of view, this means that Stylo takes in Gecko's C++ DOM tree. It parses all the CSS,
and then runs the cascade on the tree. It stores computed styles on each element in a way that Gecko can read
very cheaply.

Style computation can involve some complex steps that require calling back into C++ code. Servo's style system
is multithreaded, but Gecko is mostly designed to work off of a single main thread per process, so we need to
deal with this impedence mismatch.

Since the output of Stylo is C++-readable structs, Stylo needs to be able to read and write nontrivial C++
abstractions. Typical FFI involves passing values over a boundary, never to be seen again, however here we're
dealing with persistent state that is accessed by both sides.

To sum up, we have:

 - Lots and lots of back-and-forth FFI
 - Thread safety concerns
 - Rust code regularly dealing with nontrivial C++ abstractions
 - A need for nontrivial abstractions to be passed over FFI

All of this conspires to make for some really complicated FFI code.

 [^3]: The `em` unit is font-size-relative, so `2em` with a `font-size` of `12px` is computed to `2 * 12 = 24px`.
 [^1]: The _cascade_ in "Cascading Style Sheets" is the process used to take all the potential rules which could apply to an element and find the "most applicable" one that gets actually used.

# The actual techniques

I'll try to structure this so that the more broadly useful (and/or less gnarly) techniques come earlier in the post.

## Basic bindgen

[Bindgen][bindgen] is a tool that generates Rust bindings for structs and functions from the provided C or C++ header files. It's often used for writing Rust bindings to existing C/C++ libraries, however it's useful for integrations as well.

To use it for an integration, write a header file containing the functions your Rust code needs (referencing structs from other header files if necessary), and [run bindgen on it][run-bindgen]. For some codebases, doing this once and
checking in the generate file suffices, but if your C++ code is going to change a lot, [run it as a build dependency instead][bindgen-build-dep]. Beware that this can adversely impact build times, since your Rust build now has a partial
C++ compilation step.

For large C++ codebases, pulling in a single header will likely pull in a _lot_ of stuff. You should [whitelist], [blacklist], and/or mark things as [opaque] to reduce the amount of bindings generated. It's best to go the whitelisting route &mdash; give bindgen a whitelisted list of functions / structs to generate bindings for, and it will transitively generate bindings for any dependencies they may have. Sometimes even this will end up generating a lot, it's sometimes worth finding structs you're not using and marking them as opaque so that their bindings aren't necessary. Marking something as opaque replaces it with an array of the appropriate size and alignment, so from the Rust side it's just some bits you don't care about and can't introspect further.

Bindgen [_does_ support some C++ features][bindgen-cpp] (you may need to pass `-x c++`). This is pretty good for generating bindings to e.g. templated structs. However, it's not possible to support _all_ C++ features here, so you may need to blacklist, opaqueify, or use intermediate types if you have some complicated C++ abstractions in the deps. You'll typically get an error when generating bindings or when compiling the generated bindings, so don't worry about this unless that happens.

Bindgen is _quite_ configurable. Stylo has a [script][build_gecko] that consumes a [large toml file][servobindings.toml] containing all of the configuration.

 [bindgen]: https://github.com/rust-lang-nursery/rust-bindgen/
 [run-bindgen]: https://rust-lang-nursery.github.io/rust-bindgen/command-line-usage.html
 [bindgen-build-dep]: https://rust-lang-nursery.github.io/rust-bindgen/tutorial-1.html
 [whitelist]: https://rust-lang-nursery.github.io/rust-bindgen/whitelisting.html
 [blacklist]: https://rust-lang-nursery.github.io/rust-bindgen/blacklisting.html
 [opaque]: https://rust-lang-nursery.github.io/rust-bindgen/opaque.html
 [bindgen-cpp]: https://rust-lang-nursery.github.io/rust-bindgen/cpp.html
 [build_gecko]: https://searchfox.org/mozilla-central/rev/819cd31a93fd50b7167979607371878c4d6f18e8/servo/components/style/build_gecko.rs
 [servobindings.toml]: https://searchfox.org/mozilla-central/source/layout/style/ServoBindings.toml

## cbindgen

We don't use [cbindgen] in Stylo, but it's used for Webrender. It does the inverse of what bindgen does: given a Rust crate, it generates C headers for its public `extern "C"` API. It's also quite configurable.

 [cbindgen]: https://github.com/eqrion/cbindgen

## cxx

[cxx] is the cool new hotness in 2021, which kind of approaches the problem from both sides, enabling you to write Rust bindings for C++ and C++ bindings for Rust. It's definitely worth checking out, a lot of the things that are hard to make work with bindgen are trivial in cxx. For example, it automatically figures out what types need to be opaque, it automatically converts between `&T` and `T*` across FFI, and it is overall more targeted for the use case of an FFI layer where Rust and C++ both call each other. 


## Bindgen-aided C++ calling Rust

So bindgen helps with creating things for Rust to call and manipulate, but not in the opposite direction. cbindgen can help here, but I'm not sure if it's advisable to have _both_ bindgen and cbindgen operating near each other on the same codebase.

In Stylo we use a bit of a hack for this. Firstly, all FFI functions defined in C++ that Rust calls are declared in [one file][servobindings], and are all named `Gecko_*`. Bindgen supports regexes for things like whitelisting, so this naming scheme makes it easy to deal with.

We also declare the FFI functions defined in Rust that C++ calls in [another file][sbl], named `Servo_*`. They're also all [defined in one place][glue.rs]

However, there's nothing ensuring that the signatures match! If we're not careful, there may be mismatches, causing bad things to happen at link time or runtime. We use a small [autogenerated][autogenerator] [unit test][unit-test] to ensure the validity of the signatures.

This is especially important as we do things like type replacement, and we need tests to ensure that the rug isn't pulled out from underneath us.

 [servobindings]: https://searchfox.org/mozilla-central/rev/819cd31a93fd50b7167979607371878c4d6f18e8/layout/style/ServoBindingList.h
 [sbl]: https://searchfox.org/mozilla-central/rev/819cd31a93fd50b7167979607371878c4d6f18e8/layout/style/ServoBindingList.h
 [glue.rs]: https://searchfox.org/mozilla-central/rev/819cd31a93fd50b7167979607371878c4d6f18e8/servo/ports/geckolib/glue.rs
 [autogenerator]: https://searchfox.org/mozilla-central/rev/819cd31a93fd50b7167979607371878c4d6f18e8/servo/ports/geckolib/tests/build.rs
 [unit-test]: https://searchfox.org/mozilla-central/rev/819cd31a93fd50b7167979607371878c4d6f18e8/servo/ports/geckolib/tests/servo_function_signatures.rs



## Type replacing for fun and profit

Using [blacklisting][blacklist] in conjunction with the `--raw-line`/`raw_line()` flag, one can effectively ask bindgen to "replace" types. Blacklisting asks bindgen not to generate bindings for a type, however bindgen will continue to generate bindings _referring_ to that type if necessary. (Unlike opaque types where bindgen generates an opaque binding for the type and uses it everywhere). `--raw-line` lets you request bindgen to add a line of raw rust code to the file, and such a line can potentially define or import a new version of the type you blacklisted. Effectively, this lets you replace types.

Bindgen generates unit tests ensuring that the layout of your structs is correct (run them!), so if you accidentally replace a type with something incompatible, you will get warnings at the struct level (functions may not warn).


There are various ways this can be used:

### Safe references across FFI

_Note from 2021: [cxx] does this automatically_

Calling into C++ (and accepting data from C++) is unsafe. However, there's no reason we should have to worry about this more than we have to. For example, it would be nice if accessor FFI functions (take a foreign object, return something from inside it) could use lifetimes. And if nullability were represented on the FFI boundary so that you
don't miss null checks (and can assume non-nullness when the C++ API is okay with it).

In Stylo, we have lots of functions like the following:

```cpp
RawGeckoNodeBorrowedOrNull Gecko_GetLastChild(RawGeckoNodeBorrowed node);
```

which bindgen translates to:

```rust
extern "C" {
    fn Gecko_GetLastChild(x: &RawGeckoNode) -> Option<&RawGeckoNode>;   
}
```

Using the [bindgen build script][build_gecko] on a provided [list of borrow-able types][borrow-list], we've told bindgen that:

 - `FooBorrowedOrNull` is actually `Option<&Foo>`
 - `FooBorrowed` is actually `&Foo`

`Option<&Foo>` [is represented as a single nullable pointer in Rust][nomicon-nonnull], so this is a clean translation. 
We're forced to null-check it, but once we do we can safely assume that the reference is valid. Furthermore, due to lifetime elision the actual signature of the FFI function is `fn Gecko_GetLastChild<'a>(x: &'a RawGeckoNode) -> Option<&'a RawGeckoNode>`, which ensures we won't let the returned reference outlive the passed reference. Lifetime elision means that we can call C++ functions "safely" with the appropriate lifetime requirements, even though C++ has no such concept!


Note that this is shifting some of the safety invariants to the C++ side: We rely on the C++ to give us valid references, and we rely on it to not have nulls when the type is not marked as nullable. Most C++ codebases internally rely on such invariants for safety anyway, so this isn't much of a stretch.

We do this on both sides, actually: Many of our Rust-defined `extern "C"` functions that C++ calls get to be internally-safe because the types let us assume the validity of the pointers obtained from C++.




 [borrow-list]: https://searchfox.org/mozilla-central/rev/819cd31a93fd50b7167979607371878c4d6f18e8/layout/style/ServoBindings.toml#648-671
 [nomicon-nonnull]: https://doc.rust-lang.org/nomicon/repr-rust.html

### Making C++ abstractions Rust-accessible

A very useful thing to do here is to replace various C++ abstractions with Rust versions of them that share semantics. In Gecko, most strings are stored in `nsString`/`nsAString`/etc.

We've written an [nsstring] crate that represents layout-compatible `nsString`s in a more Rusty way, with Rusty APIs. We then ask bindgen to replace Gecko `nsString`s with these.

Usually it's easier to just write an impl for the bindgen-generated abstraction, however sometimes you must replace it:

 - When the abstraction internally does a lot of template stuff not supported by bindgen
 - When you want the code for the abstraction to be in a separate crate


 [nsstring]: https://searchfox.org/mozilla-central/rev/6ddb5fb144993fb5de044e2e8d900d7643b98a4d/servo/support/gecko/nsstring/src/lib.rs

## Potential pitfall: Passing C++ classes by-value over FFI

It's quite tempting to do stuff like

```cpp
RefPtr<Foo> Servo_Gimme(...);
```

where you pass complicated classes by-value over FFI (`RefPtr` is Gecko's variant of `Rc<T>`/`Arc<T>`).

This works on some systems, but is broken on MSVC:
[The ABI for passing non-POD types through functions is different][abi-bug]. The linker usually notices this and complains, but it's worth avoiding this entirely.

In Stylo we handle this by using some macro-generated intermediate types which are basically the same thing as the original class but without any constructors/destructors/operators. We convert to/from these types immediately before/after the FFI call, and on the Rust side we do similar conversions to Rust-compatible abstractions.




 [abi-bug]: https://github.com/rust-lang/rust/issues/38258


## Sharing abstractions with destructors

If you're passing ownership of collections or other templated types across FFI, you probably want Rust code to be able to destroy C++ objects, and vice versa.

One way of doing this is to implement `Drop` on the generated struct. If you have `class MyString`, you can do:

```cpp
class MyString {
    // ...
    ~MyString();
}

void MyString_Destroy(*MyString x) {
    x->~MyString()
}
```

```rust
impl Drop for bindings::MyString {
    fn drop(&mut self) {
        // (bindgen only)
        bindings::MyString::destruct(self)
        // OR
        bindings::MyString_Destroy(self)
    }
}
```

The `MyString_Destroy` isn't necessary with bindgen -- bindgen will generate a `MyString::destruct()` function for you -- but be careful, this will make your generated bindings very platform-specific, so be sure to only do this if running them at build time. In general, when bindgen generates C++ _methods_, your bindings become platform specific and are best regenerated at build time[^4].

In Stylo we went down the route of manually defining `_Destroy()` functions since we started off with checked-in platform-agnostic bindings, however we could probably switch to using `destruct()` if we want to now.

When it comes to generic types, it's a bit trickier, since `Drop` can't be implemented piecewise on a generic type (you cannot `impl Drop for MyVector<Foo>`). You have to do something like:

```cpp
template<typename T>
class MyVector {
    // ...
}

void MyVector_Deallocate_Buffer(MyVector<void>* x);
```

```rust
// assume we have an implementation of Iterator for MyVector<T> somewhere

impl<T> Drop for bindings::MyVector<T> {
    fn drop(&mut self) {
        for v in self.iter_mut() {
            // calls the destructor for `v`, if any
            std::ptr::drop_in_place(v)
        }
        bindings::MyVector_Deallocate_Buffer(self as *mut MyVector<T> as *mut MyVector<c_void>)
    }
}

```

Note that if you forget to add a `Drop` implementation for `T`, this will silently forget to clean up the contents of the vector. See [the next section](#mirror-types) for some ways to handle this by creating a "safe" mirror type.

 [^4]: C++ name mangling <a href="https://en.wikipedia.org/wiki/Name_mangling#How_different_compilers_mangle_the_same_functions">is not standardized</a>, so any function with the C++ ABI will generate a `#[link_name = "_Z1foobarbaz"]` attribute on the Rust side, and the exact string used here will differ across compiler implementations and platforms. Since GCC and Clang follow the same scheme, most people will encounter this problem when their code doesn't work on Windows due to MSVC using a different scheme.

## Mirror types

C++ libraries often have useful templated abstractions, and it's nice to be able to manipulate them from Rust. Sometimes, it's possible to just tack on semantics on the Rust side (either by adding an implementation or by doing type replacement), but in some cases this is tricky.

For example, Gecko has `RefPtr<T>`, which is similar to `Rc<T>`, except the actual refcounting logic is up to `T` to implement (it can choose between threadsafe, non-threadsafe, etc), which it does by writing `AddRef()` and `Release()` methods.


We mirror this in Rust by having a trait:

```rust
/// Trait for all objects that have Addref() and Release
/// methods and can be placed inside RefPtr<T>
pub unsafe trait RefCounted {
    /// Bump the reference count.
    fn addref(&self);
    /// Decrease the reference count.
    unsafe fn release(&self);
}

/// A custom RefPtr implementation to take into account Drop semantics and
/// a bit less-painful memory management.
pub struct RefPtr<T: RefCounted> {
    ptr: *mut T,
    _marker: PhantomData<T>,
}
```

We implement the `RefCounted` trait for C++ types that are wrapped in `RefPtr` which we wish to access through Rust. We have [some][rust-refcount-macro] [macros][cpp-refcount-macro] that make this easier to do. We have to have such a trait, because otherwise Rust code wouldn't know how to manage various C++ types.

However, `RefPtr<T>` here can't be the type that ends up being used in bindgen. Rust doesnt let us do things like `impl<T: RefCounted> Drop for RefPtr<T>` [^2], so we can't effectively make this work with the bindgen generated type unless we write a `RefCounted` implementation for every refcounted type that shows up in the bindgen output at all -- which would be a lot of work.

Instead, we let bindgen generate its own `RefPtr<T>`, called `structs::RefPtr<T>` (all the structs that bindgen generates for Gecko go in a `structs::` module). `structs::RefPtr<T>` itself doesn't have enough semantics to be something we can pass around willy-nilly in Rust code without causing leaks. However, it has [some methods][structs-refptr-methods] that allow for conversion into the "safe" mirror `RefPtr<T>` (but only if `T: RefCounted`). So if you need to manipulate a `RefPtr<T>` in a C++ struct somewhere, you immediately use one of the conversion methods to get a safe version of it first, and _then_ do things to it. Refcounted types that don't have the `RefCounted` implementation won't have conversion methods: they may exist in the data you're manipulating, however you won't be able to work with them.

In general, whenever attaching extra semantics to generic bindgen types doesn't work create a mirror type that's completely safe to use from Rust, with a trait that gates conversion to the mirror type.

 [rust-refcount-macro]: https://searchfox.org/mozilla-central/rev/cfaa5a1d48d6bc6552199e73004ecb05d0a9c921/servo/components/style/gecko_bindings/sugar/refptr.rs#258-315
 [cpp-refcount-macro]: https://searchfox.org/mozilla-central/rev/cfaa5a1d48d6bc6552199e73004ecb05d0a9c921/layout/style/GeckoBindings.h#52-60
 [^2]: `Drop` impls are restricted in a bunch of ways for safety, in particular you cannot write `impl<T: RefCounted> Drop for RefPtr<T>` unless `RefPtr` is defined as `RefPtr<T: RefCounted>`. It's not possible to have a generic type that has an impl of `Drop` for only _some_ possible instantiations of its generics.
 [structs-refptr-methods]: https://searchfox.org/mozilla-central/rev/cfaa5a1d48d6bc6552199e73004ecb05d0a9c921/servo/components/style/gecko_bindings/sugar/refptr.rs#150-234

## Potential pitfall: Allocators

If you're passing heap-managed abstractions across FFI, be careful about which code frees which objects. If your Rust
and C++ code don't share allocators, deallocating memory allocated on the other side can have disastrous consequences.

If you're building a cdylib or staticlib with Rust (this is likely if you're linking it with a C++ application), the compiler will by default pick the system allocator (`malloc`), so if your C++ application also uses the same you're all set.

On some platforms when building rlibs and binaries, Rust may choose jemalloc instead. It's also possible that your C++ code uses a different allocator (lots of applications use allocators like jemalloc or tcmalloc, some have their own custom allocators like `tor_malloc` in Tor).

In such cases you have one of three options:

 - Avoid transferring ownership of heap-allocated items, only share things as borrowed references
 - Call destructors over FFI, as detailed in [the section on destructors above](#sharing-abstractions-with-destructors)
 - Set Rust's allocator to be the same as documented [in the `std::alloc` module][stdalloc]. Basically, can use the `#[global_allocator]` attribute to select which allocator you wish to use, and if necessary you can implement the `GlobalAlloc` trait on a custom allocator type that calls into whatever custom allocator C++ is using.

_Note from 2021: Most stdlib collections ([`Vec`], for example) now have an optional "custom allocator" parameter that can be used to swap in a different allocator for a specific use site._


 [stdalloc]: https://doc.rust-lang.org/nightly/std/alloc/#the-global_allocator-attribute
 [`Vec`]: https://doc.rust-lang.org/nightly/std/vec/struct.Vec.html

## Arcs over FFI: Triomphe

This isn't really a generalizable technique, but it's pretty cool and generally instructive, so I'm including it here.

Stylo uses a lot of `Arc`s. A _lot_ of them. The entire computation of styles makes heavy use of `Arc::make_mut`'s copy-on-write semantics so that we can build up the style tree in parallel but not have to make unnecessary copies of duplicated/defaulted styles for each element.

Many of these `Arc`s need to be readable from C++. Rust's `Arc`, however, consists of a pointer to an allocation containing a refcount and the data, so if C++ needs to get access to the data it needs to know the layout of the `Arc` allocation, which we'd rather not do[^5].

We picked a different route: We created a crate duplicating `Arc<T>` which behaves almost exactly the same as `Arc<T>`, but it can be converted to `OffsetArc<T>` which has its pointer point to the _middle_ of the allocation, where the `T` begins. To C++, this just looks like a `*const T`! We were then able to make it work with `RefPtr<T>` on the C++ side so that C++ can transparently read from the `OffsetArc<T>`, and only needs to call into Rust if it wishes to clone or drop it.

The external version of this crate can be found in [triomphe]. It contains a bunch of other goodies that are additionally useful outside of the FFI world, like `ArcBorrow` which is essentially "`&Arc<T>` without double indirection", `UniqueArc<T>`, a mutable `Arc<T>` known to be uniquely owned, and `ArcUnion<T, U>`, which is a space-efficient union of `Arc<T>` and `Arc<U>`.


 [^5]: Rust's standard library does not typically guarantee anything about the layout of its types, and furthermore, Rust does not make many guarantees about the stability of most types without a `#[repr]` attribute. This would _work_, but it would be brittle and prone to breakage.
 [triomphe]: https://docs.rs/triomphe

## Other pitfalls

### Transparent

It's _very_ tempting to wrap C++ types in tuple structs and pass them over FFI. For example, one might imagine that the following is okay:

```rust
struct Wrapper(bindings::SomeCppType);

extern "C" {
    // C++ signature: `SomeCppType get_cpp_type();`
    fn get_cpp_type() -> Wrapper;
}
```

This kind of thing is quite useful to get around coherence, or for adding additional semantics to a type.

While there's basically one obvious way `Wrapper` can be represented, ABI stuff can be tricky, and Rust's layout isn't defined. It is safer to use `#[repr(transparent)]`, which guarantees that `Wrapper` will have the same representation as the type it contains.

### C enums

Rust supports C-like enums, but there's a crucial difference between them. In C, it is not undefined behavior for an enum to have an unlisted value. In fact, the following pattern is not uncommon:

```c
enum Flags {
    Flag1 = 0b0001,
    Flag2 = 0b0010,
    Flag3 = 0b0100,
    Flag4 = 0b1000;
};
```

where the enum is actually used for bitflags, and `Flag1 | Flag2` and `0` are both valid values for `Flags`.

This is not the case in Rust. If you are type-replacing C enums with Rust ones, make sure they are `#[repr(C)]`. The Rust compiler uses invalid enum values as space for packing other information while optimizing types, for example Rust is able to represent `Option<Option<... 255 times .. Option<bool>>` as a single byte.

If you are working with a C enum that is used for bitflags like above, please use an integer type instead. `#[repr(C)]` on enums in Rust guarantees layout, but it is [still undefined behavior for any enum to take on invalid values][ub-repr].

 [ub-repr]: https://doc.rust-lang.org/stable/nomicon/other-reprs.html


### ABI concerns

ABIs can be tricky. If you _just_ use bindgen with no special flags, you can be pretty much guaranteed to have an okay ABI, but as you start doing type replacements, stuff can get murkier.

Firstly, make sure you're not passing owned C++ classes with destructors/etc across FFI boundaries. See [above][cpp-classes-pitfall] for why. There's a bunch of subtle stuff here, but you can avoid most of it it if you just don't pass these things across FFI in an owned way.

Also, try to make sure everything is `#[repr(C)]` across the boundary. Rust's `improper-ctypes` lints will help here.

 [cpp-classes-pitfall]: #potential-pitfall-passing-c-classes-by-value-over-ffi


##  Should C++ APIs be unconditionally `unsafe`?


I recall when [this Chromium post][chromium-interop] and [Steve's `cxx` post][steve-cxx] came out, there was a bunch of brouhaha about C++ functions not being universally marked `unsafe`. Essentially, a lot of people are of the opinion that all FFI into C++ (or C) should be unconditionally marked `unsafe` (and that tools like `cxx` should follow these rules).

Back then I wrote [a Reddit comment][manishearth-cxx-comment] about my thoughts on this. It's a comment that's the length of a blog post in and of itself so I'm not going to reproduce all of it here, but I'll try to get the gist. I highly suggest you read it instead of this section.

In short, I would recommend people doing heavy C++ interop to be generally okay with marking functions calling into C++ as "safe" provided that function would be considered "safe to call without thinking too much about it" on the C++ side, whatever that means for your codebase.

From [my post on "undefined" vs "unsafe"][undefined-unsafe], for Rust I define "safe" as

> Basically, in Rust a bit of code is “safe” if it cannot exhibit undefined behavior under all circumstances of that code being used.

C++ doesn't have a rigid language-level concept of safety that can be applied the same way. Instead, most C++ code follows a similar heuristic:

> a bit of code is "safe" if it cannot exhibit undefined behavior under all **expected** circumstances of that code being used.

This is, perhaps, not as good or useful a heuristic as the one we have for Rust, but it's still a heuristic that gets used in deciding how careful one needs to be when using various APIs. After all, there are _plenty_ of giant C++ codebases out there, they have got to be able to reason about safety _somehow_.

When you decide to meld together a C++ and Rust codebase, or start rewriting parts of a C++ codebase in Rust, you have already in essence decided for a large part of the codebase to not exactly follow Rust's safety rules (but hopefully still be safe). There is little to be gained by making that an explicit part of your FFI boundary. Rather, it is more useful to save `unsafe` on the FFI boundary for truly unsafe functions which you actually do need to be careful to call.

`unsafe` is useful for finding potential sources of badness in your codebase. For a tightly-integrated Rust/C++ codebase it's already well known that the C++-side is introducing badness, marking every simple C++ getter as `unsafe` will lead to alarm fatigue and make it _harder_ to find the real problems.

It's worth figuring out where this boundary lies for you. Tools like `cxx` make it straightforward to call C++ functions through a safe interface, and it's valuable to make use of that support.


 [chromium-interop]: https://www.chromium.org/Home/chromium-security/memory-safety/rust-and-c-interoperability
 [steve-cxx]: https://steveklabnik.com/writing/the-cxx-debate
 [manishearth-cxx-comment]: https://www.reddit.com/r/rust/comments/ielvxu/the_cxx_debate/g2jurb3/?context=3
 [undefined-unsafe]: https://manishearth.github.io/blog/2017/12/24/undefined-vs-unsafe-in-rust/

## Closing comments

Again, before going down this route it's worth wondering if you _really_ need tight Rust-C++ integration. When possible, it's always better to pick a small, well-defined API boundary, rather than Stylo-esque tight integration with shared objects and a highly criscrossed callgraph.

These days [cxx][cxx] is probably the most complete tool for such integrations. [bindgen] and [cbindgen] are still quite good, but cxx is C++-first, with a lot more magic, and generally seems to Just Work without too much configuration.

[autocxx] is a cool concept by Adrian Taylor which melds bindgen and cxx to make something even _more_ magical. It's currently experimental, but I'm going to be watching it with interest.

Overall the field of Rust and C++ integration is at a stage where it's mature enough for integrations to be _possible_ without too much effort, but there are still tons of ways things could be improved and I'm super excited to see that happen as more people work on such integrations!

 [autocxx]: https://github.com/google/autocxx