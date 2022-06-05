---
layout: post
title: "Vision Zero-Copy part 2: Zero-Copy all the things"
date: 2021-04-05 08:32:30 -0700
comments: true
categories: ["mozilla", "programming", "rust"]
---


_This is part 2 of a two-part series on interesting abstractions for zero-copy deserialization I've been working on recently. Part 1 can be found [here][part 1]._


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

## Brobdingnagian Bewilderment

The short answer is: endianness, alignment, and for `Vec<String>`, indirection.


See, the way zero-copy deserialization works is by directly taking a pointer to the memory and declaring it to be the desired value. For this to work, that data _must_ be of a kind that looks the same on all machines, and must be legal to take a reference to.

This is pretty straightforward for `[u8]` and `str`, their data is identical on every system. The borrowed version of `Vec<String>`, `&[&str]` is unlikely to look the same even across different executions of the program on the _same system_, because it contains pointers (indirection) that'll change each time depending on the data source!

Pointers are hard. What about `Vec<u32>`/`[u32]`? Surely there's nothing wrong with a pile of integers?

{% imgcaption center /images/post/castlevania-data.png 400 %}<small>Dracula, dispensing wisdom on the subject of zero-copy deserialization.</small>{% endimgcaption %}




 [part 1]: @@@
 [ICU4X]: https://github.com/unicode-org/icu4x
 [`serde`]: https://docs.rs/serde
 [`rkyv`]: https://docs.rs/rkyv
 


 [^1]: A _locale_ is typically a language and location, though it may contain additional information like the writing system or even things like the calendar system in use.
 [^2]: Bear in mind, this isn't just a matter of picking a format like MM-DD-YYYY! Dates in just US English can look like `4/10/22` or `4/10/2022` or `April 10, 2022`, or `Sunday, April 10, 2022 C.E.`, or `Sun, Apr 10, 2022`, and that's not without thinking about week numbers, quarters, or time! This quickly adds up to a decent amount of data for each locale.
