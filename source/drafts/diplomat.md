---
layout: post
title: "Diplomat: Multi-language FFI for Rust libraries"
date: 2024-08-20 08:32:30 -0700
comments: true
categories: ["rust"]
---

For the past few years, as a part of my work on [ICU4X], I've been working on [Diplomat], a multi-language unidirectional FFI tool for wrapping Rust libraries.


I originally [designed][design-doc] Diplomat in 2021 as a response to the question "What is the best way to expose ICU4X (A Rust library) to other programming languages?". For context, while written in Rust, one of ICU4X's core design goals was to be available to any programming language, starting with a core set and expanding over time. This is in contrast to the existing Unicode libraries [ICU4C] and [ICU4J], which serve C/C++ and Java respectively.

In the long run, for such a project, tooling becomes a necessity. If ICU4X was just being exposed to a single language, this could potentially be feasible: someone manually writes FFI for every new API that gets written in Rust, and you need to ramp up at least part of the team on writing FFI for one particular language. However, as the number of languages you wish to support grows, this becomes more and more untenable. It is unreasonable to expect most members of an engineering team to be experts on the FFI peculiarities of C++, JS, Dart, the JVM, etc.

When we were getting started, I performed [an investigation][tooling-investigation] of the available tooling at the time, and arrived at the conclusion that none of the existing tools served our use case: a library in Rust wishing to expose an API to multiple languages. Some of these tools answered part of the story but would need to be stitched together with other work. I also wrote down a design for my "pie in the sky FFI tool" that I figured would be too much of a yak shave to build, but would fill this gap in the Rust FFI tooling ecosystem I have felt for a long time. In the meantime, we stuck to manually written C bindings as we were still figuring stuff out.


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

Bidirectional tools can often be used for unidirectional use cases, but they are also usually designed with those two specific languages in mind, which constrains the utility of the underlying bindings for work with other languages. You can't use the bindings as a neutral "hub" that many languages radiate out from.

## A wishlist for an FFI tool

When designing Diplomat, there were several things I had in mind that may not necessarily match choices made by other FFI tools:


### No action-at-a-distance

Editing your regular library Rust code should never silently change your FFI layer. I did not want Diplomat to parse the full dependency graph: it should be abundantly clear when an edit to code is going to change the FFI layer, by restricting what Diplomat consumes to specially-tagged "bridge"[^2] code. In ICU4X, the FFI layer only changes when people update the Diplomat "bridge" code living under [`ffi/capi`][icu4x-capi].

{% discussion pion-confused %}

Why is this a useful property for a tool to have?

{% enddiscussion %}

For one, it's just _easier_ to design a tool when it does not need to parse the full range of what Rust supports. Since Diplomat's "bridge" code is only intended for consumption from Diplomat, we can forbid weird Rust things from being used there.

{% discussion pion-minus %}

That means _you_, `for<'a>`.

{% enddiscussion %}

Secondly, the FFI tool should not overly constrain the API exposed to regular Rust users; it should be possible to tailor that API to Rust user's needs without having to think about other languages.

Finally, it's extremely annoying for library developers if every part of their library is being monitored by a tool which may need to be worked around / pacified. ICU4X developers absolutely need to know how to operate Diplomat so that they can write FFI for every ICU4X API they design, however ought not need to _constantly_ think about it when just designing the primary Rust code.

### Generate a ready-to-use library

Diplomat should generate a ready-to-use library, not low level bindings. As such it should generate APIs that are idiomatic in the target language, and expose some degree of per-language configurability to allow the developer choices in how precisely to expose various functionality.

### No IDLs

Ideally, the interface is smoothly specified in Rust code, rather than using some interface description language. This is an aesthetic choice; IDLs can work really well as well, and this is an option made available by [uniffi].

### Extensible for more languages

It should not be super hard to extend Diplomat to be able to produce bindings for more languages. The vision was that if we have people asking for a Dart API in ICU4X, we can write a Diplomat "backend" for Dart, and run it on the preexisting ICU4X Diplomat bridge code.


{% discussion pion-plus %}

In fact, that's exactly what happened, and ICU4X now has [a Dart API][icu4x-dart].

 [icu4x-dart]: https://github.com/unicode-org/icu4x/tree/main/ffi/capi/bindings/dart

{% enddiscussion %}

This means that Diplomat's constraints and design should from the get-go take into account the diversity of languages it may end up supporting: if a feature does not make sense for a particular language, it may need to be redesigned or made conditional.


{% discussion pion-plus %}

This also means that third parties can build their own Diplomat backends if they wish, either by using Diplomat as a library, or by contributing upstream. This has happened multiple times: the Kotlin and Python backends were not written by the ICU4X team, though ICU4X now uses the Kotlin backend and is considering using the Python one!

{% enddiscussion %}

An additional facet of extensibility is that Diplomat _features_ themselves ought not to need support in all backends. If the person developing the Kotlin backend wants callback support, they need not figure out how to add it to all of the other backends, and the other backends also need not worry about callbacks for the most part — they can just mark it as unsupported.

This particular property has led to an explosion of features in Diplomat: at this point we have multiple users each who care about a different subset of backends, and they can each build the features they need without worrying too much about overcomplicating things for other users. Then, when those other users want those features, it's much easier for them to adopt them.

## Using Diplomat

The core workflow behind Diplomat is that you write a _single_ "bridge crate" that wraps your Rust API, which, using a proc macro generates a common underlying `extern "C"` API. You can then run `diplomat-tool` on the bridge crate, invoking individual per-language "backends" to generate idiomatic language bindings that under the hood call the same underlying `extern "C"` APIs. This hub-and-spoke model means one bridge crate backs every language you target.

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
        #[diplomat::attr(auto, constructor)]
        pub fn create(settings: Settings) -> Box<MyObject> {
            Box::new(MyObject::new(settings))
        }

        pub fn do_thing(&self) {
            self.0.do_thing();
        }
    }

}
```

This will (via a proc macro) generate `extern "C"` APIs that look something like:

```rust
extern "C" fn MyObject_new(settings: Settings) -> *mut MyObject {...}
extern "C" fn MyObject_do_thing(this: &MyObject) {...}
```

as well as adding a `repr(C)` to `Settings`.

You can then pick a supported language, run `diplomat-tool <language> <path>` and generate bindings to that path.

Currently, we have `c`, `cpp`, `js` (includes TypeScript), `dart`, `kotlin`, and `python-nanobind` backends. There's also a `java` backend being developed [in a separate repo](https://github.com/rust-diplomat/diplomat-java). We're always looking for more!

In C++, this may generate a struct `Settings` and a class `MyObject` with methods `create()` and `do_thing()`. In JS it would have a similar class, but `create()` would be a constructor, and `do_thing()` would be renamed to `doThing()`. For a further idiomatic tweak, `new MyObject()` would accept untyped objects with the same fields as `Settings` as well. In both cases, the constructor/methods will call `MyObject_new`/`MyObject_do_thing` under the hood.

Diplomat supports three kinds of "custom" user-defined types: C-like enums, structs, and "opaques". Structs are copied over the FFI boundary, whereas "opaques" wrap an underlying, opaque-to-foreign-languages Rust object that is behind an allocation and only ever passed around behind an owned or borrowed pointer. Some Diplomat backends also support traits as a fourth kind of custom type, letting the user plug in their own implementation of an interface.

Diplomat also supports `Option`s, `Result`s, and slices, mapping them to the target language's idiomatic nullability, error, and list models. For example, a Rust `Result` throws an exception in JS, Dart, and Python, but maps to Kotlin's `Result` type.

For a full list of types Diplomat supports passing across the FFI boundary, see [the types chapter in the Diplomat book][book-types].

### Customization

Diplomat supports a fair amount of customization. In the example code you can see `#[diplomat::attr(auto, constructor)]`, which means that for backends which support constructors, `create()` is a constructor. The first argument for `attr` is a `cfg`-like syntax for selecting backends, and `auto` mostly means "select backends where the attribute is supported". For constructors, Dart, JS, and Kotlin support them, but the C++ and C backends don't.


{% discussion pion-confused %}

Why doesn't the C++ backend support constructors? C++ has constructors, yes?

{% enddiscussion %}

Opaque types in C++ are behind a `unique_ptr`, and C++ doesn't let you have constructors that return other types. We might still add some way of doing constructory things in C++, but for now having to write `MyObject::create()` is fine.

Diplomat [supports a lot of customization via attributes](https://rust-diplomat.github.io/diplomat/attrs.html), and all of these can be conditioned on specific backends or feature availability:

 * `disable`: Disabling APIs. This is useful to do if a backend doesn't support features needed there, or if the API is a backend-specific optimization. You can also use `#[diplomat::cfg(cpp)]` as a shortcut for `#[diplomat::attr(not(cpp), disable)]`
 * `rename`: Renaming APIs. Can be used for overloading!
 * `namespace`: For organizing code into namespaces/submodules
 * `constructor` and `named_constructor`: For marking methods as constructors
 * `iterator`, `iterable`: For hooking in to builtin language iteration stuff, enabling things like `for i in obj`
 * `getter`, `setter`: For marking a method as an accessor
 * `indexer`, `add`, `sub`, `comparison`, etc: For overloading most builtin operators



### Demo generation

Often when talking about what a library can do, I want people to be able to play around with its API and give it different numbers. For example, in ICU4X, it's great to be able to show a progression of "look, it can format a date!" → "here's that date in a less compact format" → "here's that date in French" → "here's that date in French, in the Chinese calendar" → "here's that date in French, in the Chinese calendar, with Thai numbering", where at each step you can let people fiddle around with the parameters.

But ICU4X is a Rust library, and doing this kind of demo in Rust requires whipping out your laptop and having people tweak the code.

A while ago I realized that Diplomat already knows how to generate a JS-Wasm wrapper for your library, and it already has a good understanding of the API at a type level — which means that Diplomat can generate a web-based "demo" for most exposed APIs by chasing down constructors until it finds primitive/enum types it can ask the user for.

You can see this in action on [ICU4X's autogenerated demo page](
https://icu4x.unicode.org/2_2/demo) (try playing around with `DateFormatter.formatIso` for the date time formatting example above).


Demo generation has proven to be very valuable for us; the demo linked above works on phones and is an easy way to show off ICU4X's capabilities in an elevator pitch timeframe.

The diplomat book documents [how to set this up](https://rust-diplomat.github.io/diplomat/demo_gen/intro.html).


## Design notes

I like compiler design, and Diplomat is basically a compiler. It takes (`syn`-parsed) Rust code and transforms it through a series of intermediate representations into bindings.

Diplomat, like `rustc`, has a two layers of abstract syntax tree style IRs: it has an "AST" (abstract syntax tree) that is basically a simplified version of the AST we get from `syn`, and an "HIR" (higher level intermediate representation) which has all of the paths resolved and a bunch of typechecking done. For example, [this](https://docs.rs/diplomat_core/latest/diplomat_core/hir/enum.Type.html) is the `Type` type, which contains a bunch of different variants for the different kinds of types supported in Diplomat. The various "Path" types can all eventually be resolved via their [ids](https://docs.rs/diplomat_core/latest/diplomat_core/hir/enum.TypeId.html). 

This originates from a design constraint of the proc macro: The proc macro cannot see the whole program, just the module it is tagged on. The AST is designed to not need whole-program information. As a consequence, it is less pleasant to work with.

When doing `diplomat-tool` codegen, however, the AST is transformed into the HIR, which is *much* nicer to work with. Diplomat tries to do most of the pre-work resolving everything in the HIR, so that backends can write relatively simple transformations from the HIR into bindings.

These days the _underlying_ C ABI model for Diplomat doesn't change often, so the AST and proc macro rarely change. New features are usually added via attributes or minor changes to the HIR, and backends can choose to adopt them when they want.

Most Diplomat backends have been written by a different person: writing them is pretty easy, which was our goal!


### Lifetimes

Diplomat supports APIs like this:

```rust
impl MyType {
    fn get_foo(&self) -> &Foo {...}
}
```

In Rust, this is fine: lifetimes ensure that the returned `Foo` isn't persisted for too long. In C++, it's pretty normal to manually police lifetime constraints, so we can generate an API that returns a reference there[^cpp-lifetimes].

We can't do that in JS or other GC'd languages, however, that would be unsound: these languages expect all values to be valid as long as you hold on to them, and they do not restrict how long you can hold on to them.

What we do here is that when the JS-side `&Foo` is returned, the JS object internally contains a "lifetime edge", a reference to the `MyType` that originated the borrow. If you hold the `Foo` longer than the parent `MyType`, that's fine, `Foo` will keep its parent alive since the GC will see a reference to it.

This is pretty straightforward for this API, but gets complicated pretty quickly when you start having multiple lifetimes, structs with lifetimes, or strings[^slices-lt].

The [`borrowing_param`] module in Diplomat goes into more detail on how we handle this in Diplomat.


 [^cpp-lifetimes]: Though we [have plans](https://github.com/rust-diplomat/diplomat/issues/390) to support Clang lifetime annotations.
 [^slices-lt]: Strings in JS don't expose their storage to WASM (and they're stored in an engine-specific way anyway), so passing a string to an API requires copying it over into a temporary buffer. If you borrow from the string, you may need to persist that allocation. Slices have similar problems.
 [`borrowing_param`]: https://docs.rs/diplomat_core/latest/diplomat_core/hir/borrowing_param/index.html

## Other tools

Since Diplomat has been developed, two other tools have entered the same space. Mozilla developed [uniffi], which gives you a choice of IDLs and bridge modules, and supports Kotlin, Swift, and Python (plus some third party bindings).

There is also [BoltFFI], which supports Swift, Kotlin, Java, C#, and TypeScript. It also seems to do more work in producing nice packages. I haven't really looked closely at it, but it seems neat.

Generally I think that this model for FFI tools — where you write a single "bridge" layer and use a CLI tool to generate bindings — is a good model for libraries and I'm excited to see more of this in that space. When I started working on Diplomat, this felt like a large hole in the ecosystem.


## Shoutouts

The initial idea for Diplomat was mine, but a _lot_ of it was done by others, especially some really skilled interns, and I want to make sure they get credit.

The first version of Diplomat was basically entirely written by our intern [Shadaj], who also designed the first C, C++, and JS backends.

[Quinn], another intern, designed and implemented the AST/HIR split as well as lifetime handling. The HIR-based versions of the C++ and JS/TS backends were written by my colleagues [Shane] and [Robert] respectively. Robert also implemented the Dart backend.

[Tyler], another intern, implemented the demo backend, and has been continually adding features to Diplomat.

[jcrist1] wrote the initial Kotlin backend, and [Ellen] polished it with more features (including callback support) for use in Android.

[Walter] from Zeromatter implemented the Python backend, which Zeromatter makes heavy use of alongside the C++ backend.

 [^1]: I don't remember!
 [^2]: The naming of "bridge crates" and "bridge modules" was inspired by [cxx](https://docs.rs/cxx).

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
 [BoltFFI]: https://www.boltffi.dev
 [Quinn]: https://github.com/QnnOkabayashi
 [Shane]: https://github.com/sffc
 [Robert]: https://github.com/robertbastian
 [Tyler]: https://github.com/ambiguousname
 [jcrist1]: https://github.com/jcrist1
 [Ellen]: https://github.com/emarteca
 [Walter]: https://github.com/walter-zeromatter

