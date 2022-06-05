---
layout: post
title: "Vision Zero-Copy part 2: Zero-Copy all the things"
date: 2021-04-05 08:32:30 -0700
comments: true
categories: ["mozilla", "programming", "rust"]
---


_This is part 2 of a two-part series on interesting abstractions for zero-copy deserialization I've been working on recently. Part 1 can be found [here][part 1]. The posts can be read in any order, though the first post contains an explanation of what zero-copy deserialization_ is.


## Background

_This section is the same as in the last article and can be skipped if you've read it_

For the past year and a half I've been working full time on [ICU4X], a new internationalization library in Rust being built under the Unicode Consortium as a collaboration between various companies.

There's a lot I can say about ICU4X, but to focus on one core value proposition: we want it to be _modular_ both in data and code. We want ICU4X to be usable on embedded platforms, where memory is at a premium. We want applications constrained by download size to be able to support all languages rather than pick a couple popular ones because they cannot afford to bundle in all that data. As a part of this, we want loading data to be _fast_ and pluggable. Users should be able to design their own data loading strategies for their individual use cases.

See, a key part of performing correct internationalization is the _data_. Different locales[^1] do things differently, and all of the information on this needs to go somewhere, preferably not code. You need data on how a particular locale formats dates[^2], or how plurals work in a particular language, or how to accurately segment languages like Thai which are typically not written with spaces so that you can insert linebreaks in appropriate positions.

Given the focus on data, a _very_ attractive option for us is zero-copy deserialization. In the process of trying to do zero-copy deserialization well, we've built some cool new libraries, this article is about one of them.


## What can you zero-copy?

_If you're unfamiliar with zero-copy deserialization, refer to the explanation in the previous article._


In the [previous article][part 1] we explored how zero-copy deserialization could be made more pleasant to work with by erasing the lifetimes. In essence, we were expanding our capabilities on _what you can do with_ zero-copy data.

This article is about expanding our capabilities on _what we can make_ zero-copy data.

We previously saw this struct:

```rust
#[derive(Serialize, Deserialize)]
struct Person {
    // this field is nearly free to construct
    age: u8,
    // constructing this will involve a small allocation and copy
    name: String,
    // this may take a while
    rust_files_written: Vec<String>,
}
```

and made the `name` field zero-copy by replacing it with a `Cow<'a, str>`. However, we weren't able to do the same with the `rust_files_written` field because [`serde`] does not handle zero-copy deserialization for things other than `[u8]` and `str`. Forget nested collections like `Vec<String>` (as `&[&str]`), even `Vec<u32>` (as `&[u32]`) can't be made zero-copy easily!


This is not a fundamental restriction in zero-copy deserialization, indeed, the excellent [`rkyv`] library is able to support data like this. However, it's not as slam-dunk easy as `str` and `[u8]` and it's understandable that [`serde`] wishes to not pick sides on any tradeoffs here and leave it up to the users.

So what's the actual problem here?

## Blefuscudian Bewilderment

The short answer is: endianness, alignment, and for `Vec<String>`, indirection.


See, the way zero-copy deserialization works is by directly taking a pointer to the memory and declaring it to be the desired value. For this to work, that data _must_ be of a kind that looks the same on all machines, and must be legal to take a reference to.

This is pretty straightforward for `[u8]` and `str`, their data is identical on every system. `str` does need a validation step to ensure it's valid UTF-8, but the general thrust of zero-copy serialization is to replace expensive deserialization with cheaper validation, so we're fine with that.

On the other hand, the borrowed version of `Vec<String>`, `&[&str]` is unlikely to look the same even across different executions of the program on the _same system_, because it contains pointers (indirection) that'll change each time depending on the data source!

Pointers are hard. What about `Vec<u32>`/`[u32]`? Surely there's nothing wrong with a pile of integers?

{% imgcaption center /images/post/castlevania-data.png 400 %}<small>Dracula, dispensing wisdom on the subject of zero-copy deserialization.</small>{% endimgcaption %}

This is where the endianness and alignment come in. Firstly, a `u32` doesn't look exactly the same on all systems, some systems are "big endian", where the integer `0xABCDEF` would be represented in memory as `[0xAB, 0xCD, 0xEF]`, whereas others are "little endian" and would represent it `[0xEF, 0xCD, 0xAB]`. Most systems these days are little-endian, but not all, so you may need to care about this.

This would mean that a `[u32]` serialized on a little endian system would come out completely garbled on a big-endian system if we're naïvely zero-copy deserializing.

Secondly, a lot of systems impose _alignment_ restrictions on types like `u32`. A `u32` cannot be found at any old memory address, on most modern systems it must be found at a memory address that's a multiple of 4. Similarly, a `u64` must be at a memory address that's a multiple of 8, and so on. The subsection of data being serialized, however, may be found at any address. It's possible to design a serialization framework where a particular field in the data is forced to have a particular alignment ([rkyv has this][rkyv-alignedvec]), however it's kinda tricky and requires you to have control over the alignment of the original loaded data, which isn't a part of serde's model.

So how can we address this?

## ZeroVec and VarZeroVec

_A lot of the design here can be found explained in the [design doc]_

After [a bunch of discussions][zerovec-discussions] with [Shane], we designed [`zerovec`], a crate that attempts to solve this problem, in a way that works with [`serde`].

The core abstractions of the crate are the two types, [`ZeroVec`] and [`VarZeroVec`], which are essentially zero-copy enabled versions of `Cow<'a, [T]>`, for fixed-size and variable-size `T` types.


[`ZeroVec`] can be used with any type implementing [`ULE`] (more on what this means later), which is by default all of the integer types and can be extended to _most_ `Copy` types. It's rather similar to `&[T]`, however instead of returning _references_ to its elements, it copies them out. While [`ZeroVec`] is a `Cow`-like borrowed-or-owned type[^3], there is a fully borrowed variant [`ZeroSlice`] that it derefs to.

Similarly, [`VarZeroVec`] may be used with types implementing [`VarULE`] (e.g. `str`). It _is_ able to hand out references `VarZeroVec<str>` behaves very similarly to how `&[str]` would work if such a type were allowed to exist in Rust. You can even nest them, making types like `VarZeroVec<VarZeroSlice<ZeroSlice<u32>>>`, the zero-copy equivalent of `Vec<Vec<Vec<u32>>>`.

There's also a [`ZeroMap`] type that provides a binary-search based map that works with types compatible with either [`ZeroVec`] or [`VarZeroVec`].


So, for example, to make the following struct zero-copy:

```rust
#[derive(serde::Serialize, serde::Deserialize)]
struct DataStruct {
    nums: Vec<u32>,
    chars: Vec<char>,
    strs: Vec<String>,
}
```


you can do something like this:

```rust
#[derive(serde::Serialize, serde::Deserialize)]
pub struct DataStruct<'data> {
    #[serde(borrow)]
    nums: ZeroVec<'data, u32>,
    #[serde(borrow)]
    chars: ZeroVec<'data, char>,
    #[serde(borrow)]
    strs: VarZeroVec<'data, str>,
}
```

Once deserialized, the data can be accessed with `data.nums.get(index)` or `data.strs[index]`, etc.

Custom types can also be supported within these types with some effort, if you'd like the following complex data to be zero-copy:

```rust
#[derive(Copy, Clone, PartialEq, Eq, Ord, PartialOrd, serde::Serialize, serde::Deserialize)]
struct Date {
    y: u64,
    m: u8,
    d: u8
}

#[derive(Clone, PartialEq, Eq, Ord, PartialOrd, serde::Serialize, serde::Deserialize)]
struct Person {
    birthday: Date,
    favorite_character: char,
    name: String,
}

#[derive(serde::Serialize, serde::Deserialize)]
struct Data {
    important_dates: Vec<Date>,
    important_people: Vec<Person>,
    birthdays_to_people: HashMap<Date, Person>
}
```

you can do something like this:

```rust
// custom fixed-size ULE type for ZeroVec
#[zerovec::make_ule(DateULE)]
#[derive(Copy, Clone, PartialEq, Eq, Ord, PartialOrd, serde::Serialize, serde::Deserialize)]
struct Date {
    y: u64,
    m: u8,
    d: u8
}

// custom variable sized VarULE type for VarZeroVec
#[zerovec::make_varule(PersonULE)]
#[zerovec::derive(Serialize, Deserialize)] // add Serde impls to PersonULE
#[derive(Clone, PartialEq, Eq, Ord, PartialOrd, serde::Serialize, serde::Deserialize)]
struct Person<'data> {
    birthday: Date,
    favorite_character: char,
    #[serde(borrow)]
    name: Cow<'data, str>,
}

#[derive(serde::Serialize, serde::Deserialize)]
struct Data<'data> {
    #[serde(borrow)]
    important_dates: ZeroVec<'data, Date>,
    // note: VarZeroVec always must reference the ULE type directly
    #[serde(borrow)]
    important_people: VarZeroVec<'data, PersonULE>,
    #[serde(borrow)]
    birthdays_to_people: ZeroMap<'data, Date, PersonULE>
}
```

Unfortunately the inner "ULE type" workings are not _completely_ hidden from the user, especially for `VarZeroVec`-compatible types, but the crate does a fair number of things to attempt to make it pleasant to work with.

In general, `ZeroVec` should be used for types that are fixed-size and implement `Copy`, whereas `VarZeroVec` is to be used with types that logically contain a variable amount of data, like vectors, maps, strings, and aggregates of the same. `VarZeroVec` will always be used with a dynamically sized type, yielding references to that type.

## How it works

Most of the crate is built on the [`ULE`] and [`VarULE`] traits. Both of these traits are `unsafe` traits (though as shown above most users need not manually implement them). "ULE" stands for "unaligned little-endian", and marks types which have no alignment requirements and have the same representation across endiannesses, preferring to be identical to the @@@

 [part 1]: @@@
 [ICU4X]: https://github.com/unicode-org/icu4x
 [`serde`]: https://docs.rs/serde
 [`rkyv`]: https://docs.rs/rkyv
 [rkyv-alignedvec]: https://docs.rs/rkyv/latest/rkyv/util/struct.AlignedVec.html
 [`zerovec`]: https://docs.rs/zerovec
 [design doc]: https://github.com/unicode-org/icu4x/blob/main/utils/zerovec/design_doc.md
 [zerovec-discussions]: https://github.com/unicode-org/icu4x/issues/78#issuecomment-817090204
 [`ZeroVec`]: https://docs.rs/zerovec/latest/zerovec/enum.ZeroVec.html
 [`ZeroSlice`]: https://docs.rs/zerovec/latest/zerovec/struct.ZeroSlice.html
 [`VarZeroVec`]: https://docs.rs/zerovec/latest/zerovec/enum.VarZeroVec.html
 [`ULE`]: https://docs.rs/zerovec/latest/zerovec/ule/trait.ULE.html
 [`VarULE`]: https://docs.rs/zerovec/latest/zerovec/ule/trait.VarULE.html


 [^1]: A _locale_ is typically a language and location, though it may contain additional information like the writing system or even things like the calendar system in use.
 [^2]: Bear in mind, this isn't just a matter of picking a format like MM-DD-YYYY! Dates in just US English can look like `4/10/22` or `4/10/2022` or `April 10, 2022`, or `Sunday, April 10, 2022 C.E.`, or `Sun, Apr 10, 2022`, and that's not without thinking about week numbers, quarters, or time! This quickly adds up to a decent amount of data for each locale.
 [^3]: As mentioned in the previous post, while zero-copy deserializing, it is typical to use borrowed-or-owned types like `Cow` over pure borrowed types because it's not necessary that data in a human-readable format will be able to zero-copy deserialize.