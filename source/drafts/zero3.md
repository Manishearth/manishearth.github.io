---
layout: post
title: "So Zero It's ... Negative?  (Zero-Copy #3)"
date: 2021-04-05 08:32:30 -0700
comments: true
categories: ["mozilla", "programming", "rust"]
---


_This is part 3 of a three-part series on interesting abstractions for zero-copy deserialization I've been working on over the last year. This part is about eliminating the deserialization step entirely. Part 1 is about making it more pleasant to work with and can be found [here][part 1]; while Part 2 is about making it work for more types and can be found [here][part 2].  The posts can be read in any order, though only the first post contains an explanation of what zero-copy deserialization_ is.


> And when Alexander saw the breadth of his work, he wept. For there were no more copies left to zero.
> 
> —Hans Gruber, after designing three increasingly unhinged zero-copy crates


@@@ Potentially swap the order of part 1 and part 2.

[Part 1] of this series attempted to answer the question "how can we make zero-copy deserialization _pleasant_", while [part 2] answered "how do we make zero-copy deserialization _more useful_?".

This part goes one step further and asks "what if we could avoid deserialization altogether?".

{% discussion pion-nought%}Wait, what?{% enddiscussion %}

Bear with me.

As mentioned in the previous posts, internationalization libraries like [ICU4X] need to be able to load and manage a lot of internationalization data. ICU4X in particular wants this part of the process to be as flexible and efficient as possible. The focus on efficiency is why we use zero-copy deserialization for basically everything, whereas the focus on flexibility has led to a robust and pluggable data loading infrastructure that allows you to mix and match data sources.

Deserialization is a _great_ way to load data since it's in and of itself quite flexible! You can put your data in a neat little package and load it off the filesystem! Or send it over the network! It's even better when you have efficient techniques like zero-copy deserialization because the cost is low.


But the thing is, there is still a cost. Even with zero-copy deserialization, you have to _validate_ the data you receive. It's often a cost folks are happy to pay, but that's not always the case.

For example, you might be, say, [a web browser interested in ICU4X][firefox], and you _really_ care about startup times. Browsers typically need to set up a lot of stuff when being started up (and when opening a new tab!), and every millisecond counts when it comes to giving the user a smooth experience. Browsers also typically ship with most of the internationalization data they need already. Spending precious time deserializing data that you shipped with is suboptimal.

What would be ideal would be something that works like this:


```rust
static DATA: &Data = &serde_json::deserialize!(include_bytes!("./testdata.json"));
```

where you can have stuff get deserialized at compile time and loaded into a static. Unfortunately, Rust `const` support is not at the stage where the above code is possible whilst working within serde's generic framework, though it might be in a year or so.


You _could_ write a very unsafe version of `serde::Deserialize` that operates on fully trusted data and uses some data format that is easy to zero-copy deserialize whilst avoiding any kind of validation. However, this would still have some cost: you still have to scan the data to reconstruct the full deserialized output. More importantly, it would require a parallel universe of unsafe serde-like traits that everyone has to derive or implement, where even small bugs in manual implementations would likely cause memory corruption.


{% discussion pion-plus%}Sounds like you need some format that needs no validation or scanning to zero-copy deserialize, and can be produced safely. But that doesn't exist, does it?
{% enddiscussion %}

It does.

... but you're not going to like where I'm going with this.

{% discussion pion-plus %}Oh no.{% enddiscussion %}

There is such a format: _Rust code_. Specifically, Rust code in `static`s. When compiled, Rust `static`s are basically "free" to load, beyond the typical costs involved in paging in memory. The Rust compiler trusts itself to be good at codegen, so it doesn't need validation when loading a compiled `static` from memory. There is the possibility of codegen bugs, however we have to trust the compiler about that for the rest of our program anyway!

This is even more "zero" than "zero-copy deserialization"! Regular "zero copy deserialization" still involves a scanning and potentially a validation step, it's really more about "zero allocations" than actually avoiding _all_ of the copies. On the other hand, there's truly no copies or anything going on when you load Rust statics; it's already ready to go as a `&'static` reference!

We just have to figure out a way to "serialize to `const` Rust code" such that the resultant Rust code could just be compiled in to the binary, and people who need to load trusted data into ICU4X can load it for free!

{% discussion pion-nought %}What does "`const` code" mean in this context?{% enddiscussion %}

In Rust, `const` code essentially is code that can be proven to be side-effect-free, and it's the only kind of code allowed in `static`s, `const`s, and `const fn`s.

{% discussion pion-nought %} I see! Does this code actually have to be "constant"?{% enddiscussion %}

Not quite! Rust supports mutation and even things like for loops in `const` code! Ultimately, it has to be the kind of code that _can_ be computed at compile time with no difference of behavior: so no reading from files or the network, or using random numbers.

For a long time only very simple code was allowed in `const`, but over the last year the scope of what that environment can do has expanded greatly, and it's actually possible to do complicated things here, which is precisely what enables us to actually do "serialize to Rust code" in a reasonable way.


## `databake`

_A lot of the design here can also be found in the [design doc]. While I did the bulk of the design for this crate, it was almost completely implemented by [Robert], who also worked on integrating it into ICU4X, and cleaned up the design in the process._

Enter [`databake`] (née `crabbake`). `databake` is a crate that provides just this; the ability to serialize your types to `const` code that can then be used in `static`s allowing for truly zero-cost data loading, no deserialization necessary!

The core entry point to `databake` is the `Bake` trait:

```rust
pub trait Bake {
    fn bake(&self, ctx: &CrateEnv) -> TokenStream;
}
```

A `TokenStream` is the type typically used in Rust [procedural macros] to represent a snippet of Rust code. The `Bake` trait allows you to take an instance of a type, and convert it to Rust code that represents the same value.

The `CrateEnv` object is used to track which crates are needed, so that it is possible for tools generating this code to let the user know which direct dependencies are needed.

This trait is augmented by a [`#[derive(Bake)]`][bake-derive] custom derive that can be used to apply it to most types automatically:

```rust
// inside crate `bar`, module `module.rs`

use databake::Bake;

#[derive(Bake)]
#[databake(path = bar::module)]
pub struct Person<'a> {
   pub name: &'a str,
   pub age: u32,
}
```

As with most custom derives, this only works on structs and enums that contain other types that already implement `Bake`. Most types not involving mandatory allocation should be able to.

## How to use it


`databake` itself doesn't really prescribe any particular code generation strategy. It can be used in a proc macro or in a `build.rs`, or, even in a separate binary. ICU4X does the latter, since that's just what ICU4X's model for data generation is: clients can use the binary to customize the format and contents of the data they need.


So a typical way of using this crate might be to do something like this in `build.rs`:

```rust
use some_dep::Data;
use databake::Bake;
use quote::quote;

fn main() {
   // load data from file
   let json_data = include_str!("data.json");

   // deserialize from json
   let my_data: Data = serde_json::from_str(json_data);

   // get a token tree out of it
   let baked = my_data.bake();


   // Construct rust code with this in a static
   // The quote macro is used by procedural macros to do easy codegen,
   // but it's useful in build scripts as well.
   let my_data_rs = quote! {
      use some_dep::Data;
      static MY_DATA: Data = #baked;
   }

   // Write to file
   let out_dir = env::var_os("OUT_DIR").unwrap();
   let dest_path = Path::new(&out_dir).join("data.rs");
   fs::write(
      &dest_path,
      &my_data_rs.to_string()
   ).unwrap();

   // (Optional step omitted: run rustfmt on the file)

   // tell Cargo that we depend on this file
   println!("cargo:rerun-if-changed=src/data.json");
}
```


## What it looks like

ICU4X generates all of its test data into JSON, [`postcard`], and "baked" formats. For example, for [this JSON data representing how a particular locale does numbers][decimals-json], the "baked" data looks like [this][decimals-baked]. That's a rather simple data type, but we do use this for more complex data like [date time symbol data][datetime-baked], which is unfortunately too big for GitHub to render normally.


ICU4X's code for generating this is in [this file][icu4x-databake-file]. It's complicated primarily because ICU4X's data generation pipeline is super configurable and complicated, The core thing that it does is, for each piece of data, it [calls `tokenize()`][tokenize-call], which is a thin wrapper around [calling `.bake()` on the data and some other stuff][tokenize-body]. It then takes all of the data and organizes it into files like those linked above, populated with a static for each piece of data. In our case, we include all this generated rust code into our "testdata" crate as a module, but there are many possibilities here!

For our "test" data, which is currently 2.7 MB in the [`postcard`] format (which is optimized for being lightweight), the same data ends up being 11 MB of JSON, and 18 MB of generated Rust code! That's ... a lot of Rust code, and tools like rust-analyzer struggle to load it. It's of course much smaller once compiled into the binary, though that's much harder to measure, because Rust is quite aggressive at optimizing unused data out in the baked version (where it has ample opportunity to). From various unscientific tests, it seems like 2MB of deduplicated postcard data corresponds to roughly 500KB of deduplicated baked data. This makes sense, since one can expect baked data to be near the theoretical limit of how small the data is without applying some heavy compression. Furthermore, while we deduplicate baked data at a per-locale level, it can take advantage of LLVM's ability to deduplicate statics further, so if, for example, two different locales have _mostly_ the same data for a given data key[^1] with some differences, LLVM may be able to use the same statics for sub-data.


## Limitations

`const` support in Rust still has a ways to go. For example, it doesn't yet support creating objects like `String`s which are usually on the heap, though [they are working on allowing this][const-alloc]. This isn't a huge problem for us; all of our data already supports zero-copy deserialization, which means that for every instance of our data types, there is _some way_ to represent it as a borrow from another `static`.

A more pesky limitation is that you can't interact with traits in `const` environments. To some extent, were that possible, the purpose of this crate could also have been fulfilled by making the `serde` pipeline `const`-friendly[^2], and then the code snippet from the beginning of this post would work:

```rust
static DATA: &Data = &serde_json::deserialize!(include_bytes!("./testdata.json"));
```

This means that for things like `ZeroVec` (see [part 2]), we can't actually just make their safe constructors `const` and pass in data to be validated — the validation code is all behind traits — so we have to unsafely construct them. This is somewhat unfortunate, however ultimately if the `zerovec` byte representation had trouble roundtripping we would have larger problems, so it's not an introduction of a new surface of unsafety. We're still able to validate things when _generating_ the baked data, we just can't get the compiler to also re-validate before agreeing to compile the `const` code.

## Try it out!

[`crabbake`] is much less mature compared to [`yoke`] and [`zerovec`], but it does seem to work rather well so far. Try it out! Let me know what you think!

_Thanks to [Finch](https://twitter.com/plaidfinch), [Jane](https://twitter.com/yaahc_), [Shane], @@@@ for reviewing drafts of this post_



 [part 1]: @@@
 [part 2]: @@@
 [ICU4X]: https://github.com/unicode-org/icu4x
 [firefox]: https://www.mozilla.org/en-US/firefox/
 [`databake`]: https://docs.rs/databake
 [`yoke`]: https://docs.rs/yoke
 [`zerovec`]: https://docs.rs/zerovec
 [`postcard `]: https://docs.rs/postcard
 [procedural macros]: https://doc.rust-lang.org/reference/procedural-macros.html
 [design doc]: https://docs.google.com/document/d/192l7yr6hVnG11Dr8a7mDLonIb6c8rr6zq-iswrZtlXE/edit
 [bake-derive]: https://docs.rs/databake/0.1.1/databakee/derive.Bake.html
 [decimals-json]: https://github.com/unicode-org/icu4x/blob/7b52dbfe57043da5459c12627671a779d467dc0f/provider/testdata/data/json/decimal/symbols%401/ar-EG.json
 [decimals-baked]: https://github.com/unicode-org/icu4x/blob/7b52dbfe57043da5459c12627671a779d467dc0f/provider/testdata/data/baked/decimal/symbols_v1.rs#L24-L41
 [datetime-baked]: https://raw.githubusercontent.com/unicode-org/icu4x/7b52dbfe57043da5459c12627671a779d467dc0f/provider/testdata/data/baked/datetime/datesymbols_v1.rs
 [icu4x-databake-file]: https://github.com/unicode-org/icu4x/blob/3f4d841ef0b168031d837433d075308bbebf34b7/provider/datagen/src/databake.rs
 [tokenize-call]: https://github.com/unicode-org/icu4x/blob/3f4d841ef0b168031d837433d075308bbebf34b7/provider/datagen/src/databake.rs#L118
 [tokenize-body]: https://github.com/unicode-org/icu4x/blob/882e23403327620e4aafde28a9a407bcc6245a54/provider/core/src/datagen/payload.rs#L131-L136
 [^1]: In ICU4X, a "data key" can be used to talk about a specific type of data, for example the decimal symbols data has a `decimal/symbols@1` data key.
 [^2]: Mind you, this would not be an easy task, but it would likely integrate with the ecosystem really well.
 [const-alloc]: https://github.com/rust-lang/const-eval/issues/20
 [Robert]: https://github.com/robertbastian
 [Shane]: https://github.com/sffc