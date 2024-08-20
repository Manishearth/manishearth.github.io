---
layout: post
title: "Diplomat: Multi-language FFI for Rust libraries"
date: 2024-08-20 08:32:30 -0700
comments: true
categories: ["rust"]
---

For the past few years, as a part of my work on [ICU4X], I've been working on [Diplomat], a multi-language unidirectional FFI tool for wrapping Rust libraries.


I originally [designed][design-doc] by me in 2021 as a response to the question "What is the best way to expose ICU4X (A Rust library) to other programming languages?". For context, while written in Rust, one of ICU4X's core design goals was to be available to any programming language, starting with a core set and expanding over time. This is in contrast to the existing Unicode libraries [ICU4C] and [ICU4J], which serve C/C++ and Java respectively.

In the long run, for such a project, tooling becomes a necessity. If ICU4X was just being exposed to a single language, this could potentially be feasible: someone manually writes FFI for every new API that gets written in Rust, and you need to ramp up at least part of the team on writing FFI for one particular language. However, as the number of languages you wish to support grows, this becomes more and more untenable. It is unreasonable to expect most members of an engineering team on the FFI peculiarities of C++, JS, Dart, the JVM, etc.

When we were getting started, I performed [an investigation][tooling-investigation] of the available tooling at the time, and arrived a the conclusion that none of the existing tools served our use case: a library in Rust wishing to expose an API to multiple languages. Some of these tools answered part of the story but would need to be stitched together with other work. I also wrote down a design for my "pie in the sky FFI tool" that I figured would be too much of a yak shave to build, but would fill this gap in the Rust FFI tooling ecosystem I have felt for a long time. In the meantime, we stuck to manually written C bindings as we were still figuring stuff out.


One of the core reasons the existing FFI tools didn't work was that they weren't "unidirectional", they were "bidirectional", or "unidirectional" in the opposite direction.

{% discussion pion-confused %}

What's "unidirectional" and "bidirectional" in the context of an FFI tool?

{% enddiscussion %}

So, it's possible this is terminology I just made up one day[^1], but it's an ontology that I've found useful on many, many occasions, so I think it's worth introducing


## Unidirectional vs bidirectional FFI tools

In general when doing FFI there are, broadly speaking, two distinct possible goals, with distinct characteristics.

One use case, served by tools like [bindgen], [cbindgen], [wasm-bindgen], [uniffi], and [PyO3], is when you have a library in one language which you wish to use from another language. This is "unidirectional" FFI, since the wrapped library doesn't need to know anything about the codebase calling into it. 


{% aside note %}

Note that _calls_ in "unidirectional" FFI can still go in both ways; a unidirectional FFI tool may support things like callbacks that allow the calling codebase to pass a closure to the library and have the library invoke it. This is still unidirectional since the API definition is within the wrapped library.

{% endaside %}

The other use case, served by tools like [cxx], [autocxx], [crubit], and [swift-bridge] is where you are working on a combined codebase of two languages and need interop in "both ways", e.g. you need Rust to be able to access C++ APIs and C++ to be able to access Rust APIs. This is the kind of interop situation I recall when working on [Stylo], the project to use [Servo]'s style system in Firefox. Even with Servo being relatively modular, this was not a case of "call Servo like a library", it was a case of integrating two codebases with a somewhat jagged API boundary. At the time there was not much tooling and we managed to [convince bindgen to work for this][stylo-ffi], however this was very much a "bidirectional" use case.

Bidirectional tools can often be used for unidirectional use cases, but they are also usually designed with those two specific languages in mind, which constrains the utility of the underlying bindings for work with other languages.

## A wishlist for an FFI tool

When designing Diplomat, there were a couple things I had in mind that may not necessarily match choices made by other FFI tools:

### No action-at-a-distance

I did not want Diplomat to parse the full dependency graph: it should be abundantly clear when an edit to code is going to change the FFI layer, by restricting what Diplomat consumes to specially-tagged "bridge"[^2] code. In ICU4X, the FFI layer only changes when people update the Diplomat "bridge" code living under [`ffi/capi`][icu4x-capi].

{% discussion pion-confused %}

Why is this a useful property for a tool to have?

{% enddiscussion %}

For one, it's just _easier_ to design a tool when it does not need to parse the full range of what Rust supports. Since Diplomat's "bridge" code is only intended for consumption from Diplomat, we can forbid weird Rust things from being used there.

Secondly, the FFI tool should not overly constrain the API exposed to regular Rust users; it should be possible to tailor that API to Rust user's needs without having to think about other languages.

Finally, it's extremely annoying for library developers if every part of their library is being monitored by a tool which may need to be worked around / pacified. ICU4X developers absolutely need to know how to operate Diplomat so that they can write FFI for every ICU4X API they design, however ought not need to _constantly_ think about it when just designing the primary Rust code.

### Generate a ready-to-use library

Diplomat should generate a ready-to-use library, not low level bindings. As such it should generate APIs that are idiomatic in the target language, and expose some degree of per-language configurability to allow the developer choices in how precisely to expose various functionality.

### No IDLs

Ideally, the interface is smoothly specified in Rust code, rather than using some interface description language. This is an aesthetic choice; IDLs can work really well as well, and this is the option chosen by [uniffi].

### Extensible for more languages

It should not be super hard to extend Diplomat to be able to produce bindings for more languages. The vision was that if we have people asking for a Dart API in ICU4X, we can write a Diplomat "backend" for Dart, and run it on the preexisting ICU4X Diplomat bridge code.


{% discussion pion-plus %}

In fact, that's exactly what happened, and ICU4X now has [a Dart API][icu4x-dart].

 [icu4x-dart]: https://github.com/unicode-org/icu4x/tree/main/ffi/capi/bindings/dart

{% enddiscussion %}

This means that Diplomat's constraints and design should from the get-go take into account the diversity of languages it may end up supporting: if a feature does not make sense for a particular language, it may need to be redesigned or made conditional.


{% discussion pion-plus %}

This also means that third parties can build their own Diplomat backends if they wish, either by using Diplomat as a library, or by contributing upstream.

{% enddiscussion %}

## Using Diplomat

The core workflow behind Diplomat is that you write a _single_ "bridge crate" that wraps your Rust API, which, using a proc macro generates a common underlying `extern "C"` API. You can then run `diplomat-tool` on the bridge crate, invoking individual per-language "backends" to generate idiomatic language bindings that under the hood call the same underlying `extern "C"` APIs.

For example, you may write something like this:

```rust
#[diplomat::bridge]
mod ffi {
    pub struct Settings {
        pub something: u8,
        pub something_else: bool
    }

    #[diplomat::opaque]
    pub struct MyObject(my_library::MyObject);

    impl MyObject {
        #[diplomat::attr(supports = constructors, constructor)]
        pub fn new(settings: Settings) -> Box<MyObject> {
            Box::new(MyObject::new(settings))
        }

        pub fn do_thing(&self) {
            self.0.do_thing();
        }
    }

}
```

This will generate `extern "C"` APIs that look something like:

```rust
extern "C" fn MyObject_new(settings: Settings) -> *mut MyObject {...}
extern "C" fn MyObject_do_thing(this: &MyObject) {...}
```

as well as adding a `repr(C)` to `Settings`.

In C++, this may generate a struct `Settings` and a class `MyObject` with a constructor and a method `do_thing()`. In JS it may do something similar, though potentially `new MyObject()` would accept untyped objects with the same fields as `Settings` as well, and `do_thing()` might be called `doThing()` instead. In both cases, the constructor and the method will work by calling `MyObject_new` and `MyObject_do_thing`.


Diplomat supports three kinds of "custom" user-defined types: C-like enums, structs, and "opaques". Structs are copied over the FFI boundary, whereas "opaques" wrap an underlying, opaque-to-foreign-languages Rust object that is behind an allocation and only ever passed around behind an owned or borrowed pointer.

For a full list of types Diplomat supports passing across the FFI boundary, see [the types chapter in the Diplomat book][book-types].


## Uncat




Our intern [Shadaj] implemented the initial design of the tool, with C, C++, and JavaScript/Typescript APIs getting autogenerated for ICU4X, from a shared API definition.



 [^1]: I don't remember!
 [^2]: The naming of "bridge crates" and "bridge modules" was inspired by cxx.

 [ICU4X]: https://github.com/unicode-org/icu4x
 [Diplomat]: https://github.com/rust-diplomat/diplomat
 [design-doc]: https://github.com/rust-diplomat/diplomat/blob/main/docs/design_doc.md
 [ICU4C]: https://unicode-org.github.io/icu/userguide/icu4c/
 [ICU4J]: https://unicode-org.github.io/icu/userguide/icu4j
 [tooling-investigation]: https://docs.google.com/document/d/1Y1mNFAGbGNvK_I64dd0fRWOxx9xqi12dXeLivnxRWvA/edit?usp=sharing&resourcekey=0-l9QvvqXW7cC-TrfLWt7nZw
 [Shadaj]: https://github.com/shadaj
 [cxx]: https://github.com/dtolnay/cxx
 [autocxx]: https://github.com/google/autocxx
 [crubit]: https://github.com/google/crubit
 [Stylo]: https://bholley.net/blog/2017/stylo.html
 [Servo]: https://github.com/servo/servo/
 [stylo-ffi]: https://manishearth.github.io/blog/2021/02/22/integrating-rust-and-c-plus-plus-in-firefox/
 [swift-bridge]: https://github.com/chinedufn/swift-bridge
 [PyO3]: https://pyo3.rs/
 [bindgen]: https://github.com/rust-lang/rust-bindgen
 [cbindgen]: https://github.com/mozilla/cbindgen
 [wasm-bindgen]: https://github.com/rustwasm/wasm-bindgen
 [book-types]: https://rust-diplomat.github.io/book/types.html
 [icu4x-capi]: https://github.com/unicode-org/icu4x/tree/main/ffi/capi
 [uniffi]: https://github.com/mozilla/uniffi-rs

