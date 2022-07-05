---
layout: post
title: "Zero-Copy Stuff part 2: Zero-Copy all the things"
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

{% discussion pion-plus%}If you're unfamiliar with zero-copy deserialization, check out the explanation in the [previous article]!

 [previous article]: @@@@
{% enddiscussion %}


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

After [a bunch of discussions][zerovec-discussions] with [Shane], we designed [`zerovec`][zerovec-lib], a crate that attempts to solve this problem, in a way that works with [`serde`].

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
    // note: VarZeroVec always must reference the unsized ULE type directly
    #[serde(borrow)]
    important_people: VarZeroVec<'data, PersonULE>,
    #[serde(borrow)]
    birthdays_to_people: ZeroMap<'data, Date, PersonULE>
}
```

Unfortunately the inner "ULE type" workings are not _completely_ hidden from the user, especially for `VarZeroVec`-compatible types, but the crate does a fair number of things to attempt to make it pleasant to work with.

In general, `ZeroVec` should be used for types that are fixed-size and implement `Copy`, whereas `VarZeroVec` is to be used with types that logically contain a variable amount of data, like vectors, maps, strings, and aggregates of the same. `VarZeroVec` will always be used with a dynamically sized type, yielding references to that type.


I've noted before that these types are like `Cow<'a, T>`. They can be dealt with in a mutable-owned fashion, but it's not the primary focus of the crate. In particular, `VarZeroVec<T>` will be significantly slower to mutate than something like `Vec<String>`, since all operations are done on the same buffer format. The general idea of this crate is that you probably will be _generating_ your data in a situation without too many performance constraints, but you want the operation of _reading_ the data to be fast. So, where necessary, the crate trades off mutation performance for deserialization/read performance. Still, it's not terribly slow, just something to look out for and benchmark if necessary.


## How it works

Most of the crate is built on the [`ULE`] and [`VarULE`] traits. Both of these traits are `unsafe` traits (though as shown above most users need not manually implement them). "ULE" stands for "unaligned little-endian", and marks types which have no alignment requirements and have the same representation across endiannesses, preferring to be identical to the little-endian representation where relevant[^4].

There's also a safe [`AsULE`] trait that allows one to convert a type between itself and some corresponding `ULE` type.


```rust
pub unsafe trait ULE: Sized + Copy + 'static {
    // Validate that a byte slice is appropriate to treat as a reference to this type
    fn validate_byte_slice(bytes: &[u8]) -> Result<(), ZeroVecError>;

    // less relevant utility methods omitted
}

pub trait AsULE: Copy {
    type ULE: ULE;

    // Convert to the ULE type
    fn to_unaligned(self) -> Self::ULE;
    // Convert back from the ULE type
    fn from_unaligned(unaligned: Self::ULE) -> Self;
}

pub unsafe trait VarULE: 'static {
    // Validate that a byte slice is appropriate to treat as a reference to this type
    fn validate_byte_slice(_bytes: &[u8]) -> Result<(), ZeroVecError>;

    // Construct a reference to Self from a known-valid byte slice
    // This is necessary since VarULE types are dynamically sized and the working of the metadata
    // of the fat pointer varies between such types
    unsafe fn from_byte_slice_unchecked(bytes: &[u8]) -> &Self;

    // less relevant utility methods omitted
}
```

`ZeroVec<T>` takes in types that are `AsULE` and stores them internally as slices of their ULE types (`&[T::ULE]`). Such slices can be freely zero-copy serialized. When you attempt to index a `ZeroVec`, it converts the value back to `T` on the fly, an operation that's usually just an unaligned load.

`VarZeroVec<T>` is a bit more complicated. The beginning of its memory stores the indices of every element in the vector, followed by the data for all of the elements just splatted one after the other. As long as the dynamically sized data can be represented in a _flat_ fashion (without further internal indirection), it can implement `VarULE`, and thus be used in `VarZeroVec<T>`. `str` implements this, but so do `ZeroSlice<T>` and `VarZeroSlice<T>`, allowing for infinite nesting of `zerovec` types!


`ZeroMap<T>` works similarly to the [`litemap`] crate, it's a map built out of two vectors, using binary search to find keys. This isn't always as efficient as a hash map but it can work well in a zero-copy way since it can just be backed by `ZeroVec` and `VarZeroVec`. There's a bunch of trait infrastructure that allows it to automatically select `ZeroVec` or `VarZeroVec` for each of the key and value vectors based on the type of the key or value.

## What about rkyv?

An important question when we started down this path was: what about [`rkyv`]? It had at the time just received a fair amount of attention in the Rust community, and seemed like a pretty cool library targeting the same space.

And in general if you're looking for zero-copy deserialization, I wholeheartedly recommend looking at it! It's an impressive library with a lot of thought put into it. When we were refining [`zerovec`][zerovec-lib] we learned a lot from [`rkyv`] having some insightful discussions with [David] and comparing notes on approaches.

The main sticking point, for us, was that [`rkyv`] works kinda separately from [`serde`]: it uses its own traits and own serialization mechanism. We really liked [`serde`]'s model and wanted to keep using it, especially since we wanted to support a variety of human-readable and non-human-readable data formats, including [`postcard`], which is explicitly designed for low-resource environments. This becomes even more important for data interchange; we'd want programs written in other languages to be able to construct and send over data without necessarily being constrained to a particular wire format.

The goal of [`zerovec`] is essentially to bring [`rkyv`]-like improvements to a [`serde`] universe without disrupting that universe too much. `zerovec` types, on human-readable formats like JSON, serialize to a normal human-readable representation of the structure, and on binary formats like [`postcard`], serialize to a compact, zero-copy-friendly representation that Just Works.



## How does it perform?


So off the bat I'll mention that [`rkyv`] maintains [a very good benchmark suite][rkyv-bench] that I really need to get around to integrating with zerovec, but haven't yet.

{% discussion pion-minus%}Why not go do that first? It would make your post better!{% enddiscussion %}

Well, I was delaying working on this post until I had those benchmarks integrated, but that's not how executive function works, and at this point I'd rather publish with the benchmarks I have rather than delaying further. I might update this post with the Good Benchmarks later!

{% discussion pion-minus%}Hmph.{% enddiscussion %}

The complete benchmark run details can be found [here][bench-run] (run via `cargo bench` at [`1e072b32`][bench-hash]), I'm pulling out some specific data points for illustration:

`ZeroVec`:



<table>
<thead><th>Benchmark</th><th>Slice</th><th>ZeroVec</th></thead>
<tbody>

   <tr><th>Deserialization (with <code>bincode</code>)</th></tr>
   <tr><th>Deserialize a vector of 100 u32s</th><td>141.55 ns</td><td>12.166 ns</td></tr>
   <tr><th>Deserialize a vector of 15 chars</th><td>225.55 ns</td><td>25.668 ns</td></tr>
   <tr><th>Deserialize and then sum a vector of 20 u32s</th><td>47.423 ns</td><td>14.131 ns</td></tr>

   <tr><th>Element fetching performance</th></tr>
   <tr><th>Sum a vector of 75 u32 elements</th><td>4.3091 ns</td><td>5.7108 ns</td></tr>
   <tr><th>Binary search a vector of 1000 u32 elements, 50 times</th><td>428.48 ns</td><td>565.23 ns</td></tr>
   <tr><th>Binary search a vector of 1000 u32 elements, 50 times</th><td>428.48 ns</td><td>565.23 ns</td></tr>
   <tr><th>Serialization</th></tr>

   <tr><th>Serialize a vector of 20 u32s</th><td>51.324 ns</td><td>21.582 ns</td></tr>
   <tr><th>Serialize a vector of 15 chars</th><td>195.75 ns</td><td>21.123 ns</td></tr>
</tbody>
</table>

<br>
In general we don't care about serialization performance much, however serialization is fast here because `ZeroVec`s are always stored in memory as the same form they would be serialized at. This can make mutation slower. Fetching operations are a little bit slower on `ZeroVec`. The deserialization performance is where we see our real wins, sometimes being more than ten times as fast!

`VarZeroVec`:

The strings are randomly generated, picked with sizes between 2 and 20 code points, and the same set of strings is used for any given row.

<table>
<thead><th>Benchmark</th><th><code>Vec&lt;String&gt;</code></th><th><code>Vec&lt;&str&gt;</code></th><th>VarZeroVec</th></thead>
<tbody>

   <tr><th>Deserialize (len 100)</th><td>11.274 us</td><td>2.2486 us</td><td>1.9446 us</td></tr>

   <tr><th>Count code points (len 100)</th><td colspan=2>728.99 ns</td><td>1265.0 ns</td></tr>
   <tr><th>Binary search for 1 element (len 500)</th><td colspan=2>57.788 ns</td><td>122.10 ns</td></tr>
   <tr><th>Binary search for 10 elements (len 500)</th><td colspan=2>451.40 ns</td><td>803.67 ns</td></tr>

</tbody>
</table>
<br>

Here, fetching operations are a bit slower since they need to read the indexing array, but there's still a decent win for zero-copy deserialization. The deserialization wins stack up for more complex data; for `Vec<String>` you can get _most_ of the wins by using `Vec<&str>`, but that's not necessarily possible for something more complex. We don't currently have mutation benchmarks for `VarZeroVec`, but mutation can be slow and as mentioned before it's not intended to be used much in client code.


## Try it out!

Similar to [`yoke`], I don't consider the [`zerovec`] crate "done" yet, but it's been in use in ICU4X for a year now and I consider it mature enough to recommend to others. Try it out! Let me know what you think!

_Thanks to @@@@ for reviewing drafts of this post_




 [part 1]: @@@
 [ICU4X]: https://github.com/unicode-org/icu4x
 [`serde`]: https://docs.rs/serde
 [`rkyv`]: https://docs.rs/rkyv
 [`postcard`]: https://docs.rs/postcard
 [`litemap`]: https://docs.rs/litemap
 [rkyv-alignedvec]: https://docs.rs/rkyv/latest/rkyv/util/struct.AlignedVec.html
 [zerovec-lib]: https://docs.rs/zerovec
 [design doc]: https://github.com/unicode-org/icu4x/blob/main/utils/zerovec/design_doc.md
 [zerovec-discussions]: https://github.com/unicode-org/icu4x/issues/78#issuecomment-817090204
 [`ZeroVec`]: https://docs.rs/zerovec/latest/zerovec/enum.ZeroVec.html
 [`ZeroSlice`]: https://docs.rs/zerovec/latest/zerovec/struct.ZeroSlice.html
 [`VarZeroVec`]: https://docs.rs/zerovec/latest/zerovec/enum.VarZeroVec.html
 [`ULE`]: https://docs.rs/zerovec/latest/zerovec/ule/trait.ULE.html
 [`ULE`]: https://docs.rs/zerovec/latest/zerovec/ule/trait.AsULE.html
 [`VarULE`]: https://docs.rs/zerovec/latest/zerovec/ule/trait.VarULE.html
 [David]: https://github.com/djkoloski
 [rkyv-bench]: https://github.com/djkoloski/rust_serialization_benchmark
 [bench-run]: https://gist.github.com/Manishearth/056a0ec12f9c943d71d214713d448ac0
 [bench-hash]: https://github.com/unicode-org/icu4x/tree/1e072b3248b93a974e21f3d01bc6a165eb272554/utils/zerovec


 [^1]: A _locale_ is typically a language and location, though it may contain additional information like the writing system or even things like the calendar system in use.
 [^2]: Bear in mind, this isn't just a matter of picking a format like MM-DD-YYYY! Dates in just US English can look like `4/10/22` or `4/10/2022` or `April 10, 2022`, or `Sunday, April 10, 2022 C.E.`, or `Sun, Apr 10, 2022`, and that's not without thinking about week numbers, quarters, or time! This quickly adds up to a decent amount of data for each locale.
 [^3]: As mentioned in the previous post, while zero-copy deserializing, it is typical to use borrowed-or-owned types like `Cow` over pure borrowed types because it's not necessary that data in a human-readable format will be able to zero-copy deserialize.
 [^4]: Most modern systems are little endian, so this imposes one fewer potential cost on conversion.