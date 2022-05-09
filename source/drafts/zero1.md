---
layout: post
title: "Vision Zero-Copy part 1: Not a yoking matter"
date: 2021-04-05 08:32:30 -0700
comments: true
categories: ["mozilla", "programming", "rust"]
---

_This is part 1 of a two-part series on interesting abstractions for zero-copy deserialization I've been working on recently. Part 2 can be found [here][part 2]._


## Background

For the past year and a half I've been working full time on [ICU4X], a new internationalization library in Rust being built under the Unicode Consortium as a collaboration between various companies.

There's a lot I can say about ICU4X, but to focus on one core value proposition: we want it to be _modular_ both in data and code. We want ICU4X to be usable on embedded platforms, where memory is at a premium. We want applications constrained by download size to be able to support all languages rather than pick a couple popular ones because they cannot afford to bundle in all that data. As a part of this, we want loading data to be _fast_ and pluggable. Users should be able to design their own data loading strategies for their individual use cases.

See, a key part of performing correct internationalization is the _data_. Different locales[^1] do things differently, and all of the information on this needs to go somewhere, preferably not code. You need data on how a particular locale formats dates[^2], or how plurals work in a particular language, or how to accurately segment languages like Thai which are typically not written with spaces so that you can insert linebreaks in appropriate positions.

Given the focus on data, a _very_ attractive option for us is zero-copy deserialization. In the process of trying to do zero-copy deserialization well, we've built some cool new libraries, this article is about one of them.


{% imgcaption center /images/post/cow-tools.png 400 %}<small>Gary Larson, ["Cow Tools"](https://en.wikipedia.org/wiki/Cow_Tools), _The Far Side_. October 1982</small>{% endimgcaption %}


## Zero-copy deserialization: the basics

_This section can be skipped if you're already familiar with zero-copy deserialization in Rust_


Deserialization typically involves two tasks, done in concert: validating the data, and constructing an in-memory representation that can be programmatically accessed; i.e., the final deserialized value.

Depending on the format, the former is typically rather fast, but the latter can be super slow, typically around any variable-sized data which needs a new allocation and often a large copy.

```rust
#[derive(Serialize, Deserialize)]
struct Person {
    // this field is nearly free to construct
    age: u8,
    // constructing this will involve a small allocation and copy
    name: String,
    // this may take a while
    rust_files_written: Vec<RustFile>,
}

```

A typical binary data format will probably store this as a byte for the age, followed by the length of `name`, followed by the bytes for `name`, followed by another length for the vector, followed by whatever data is needed for each `RustFile` value. Deserializing the `u8` age just involves reading it, but the other two fields require allocating sufficient memory and copying each byte over, in addition to any validation the types may need.

A common technique in this scenario is to skip the allocation and copy by simply _validating_ the bytes and storing a _reference_ to the original data. This can only be done for serialization formats where the data is represented identically in the serialized file and in the deserialized value.

When using [`serde`] in Rust, this is typically done by using a [`Cow<'a, T>`] with `#[serde(borrow)]`:

```rust
#[derive(Serialize, Deserialize)]
struct Person<'a> {
    age: u8,
    #[serde(borrow)]
    name: Cow<'a, str>,
}

```

Now, when `name` is being deserialized, the deserializer only needs to validate that it is in fact a valid UTF-8 `str`, and the final value for `name` will be a reference to the original data being deserialized from itself.

An `&'a str` can also be used instead of the `Cow`, however this makes the `Deserialize` impl much less general, since formats that do _not_ store strings identically to their in-memory representation (e.g. JSON with strings that include escapes) will not be able to fall back to an owned value. As a result of this, owned-or-borrowed [`Cow<'a, T>`] is often a cornerstone of good design when writing Rust code partaking in zero-copy deserialization.

{% aside %}

You may notice that `rust_files_written` can't be found in this new struct. This is because [`serde`], out of the box, can't handle zero-copy deserialization for anything other than `str` and `[u8]`, for very good reasons. Other frameworks like [`rkyv`] can, however we've also managed to make this work with [`serde`]. I'll go in more depth about said reasons and our solution in [part 2].


 [`serde`]: https://docs.rs/serde
 [`rkyv`]: https://docs.rs/rkyv

{% endaside %}

## When life gives you lifetimes ....

Zero-copy deserialization in Rust has one very pesky downside: the lifetimes. Suddenly, all of your deserialized types have lifetimes on them. Of course they would; they're no longer self-contained, instead containing references to the data they were originally deserialized from!

This isn't a problem unique to Rust, either, zero-copy deserialization always introduces more complex dependencies between your types, and different frameworks handle this differently; from leaving management of the lifetimes to the user to using reference counting or a GC to ensure the data sticks around. Rust serialization libraries can also do stuff like this if they wish. In this case, [`serde`], in a very Rusty fashion, wants the library user to have control over the precise memory management here and surfaces this problem as a lifetime.


Unfortunately, lifetimes like these tend to make their way into everything. Every type holding onto your deserialized type needs a lifetime now and it's likely going to become your users' problem too.

Furthermore, Rust lifetimes are a purely compile-time construct. If your value is of a type with a lifetime, you need to know at compile time by when it will definitely no longer be in use, and you need to hold on to its source data until then. Rust's design means that you don't need to worry about getting this _wrong_, since the compiler will catch you, but you still need to _do it_.

Which isn't ideal for cases where you want to manage the lifetimes at runtime, e.g. if your data is being deserialized from a larger file and you wish to cache the loaded file as long as data deserialized from it is still around.

Typically in such cases you can use [`Rc<T>`], which is effectively the "runtime instead of compile time" version of `&'a T`s safe shared reference, but this only works for cases where you're sharing homogenous types, whereas in this case we're attempting to share different types deserialized from one blob of data, which itself is of a different type.

ICU4X would like users to be able to make use of caching and other data management strategies as needed, so this won't do at all. For a while ICU4X had not one but _two_ pervasive lifetimes threaded throughout most of its types: it was both confusing and not in line with our goals.

## ... demand life take the lifetimes back

@@ check original discussion doc for details

@@ link to design doc

After a bunch of discussion on this, with help from [Shane] I designed [`yoke`], a crate that attempts to provide _lifetime erasure_ in Rust via self-referential types.

The general idea is that you can take a zero-copy deserializeable type like a `Cow<'a, str>` (or `Person<'a>` from the previous examples) and "yoke" it to the value it was deserialized from, which we call a "cart":

```rust
// Some types explicitly mentioned for clarity

// load a file
let file: Rc<[u8]> = fs::read("data.postcard")?.into();

// create a new Rc reference to the file data by cloning it,
// then use it as a cart for a Yoke
let y: Yoke<Cow<'static, str>, Rc<[u8]>> = Yoke::attach_to_cart(file.clone(), |contents| {
    // deserialize from the file
    let cow: Cow<str> =  postcard::from_bytes(&contents);
    cow
})

// the string is still accessible with `.get()`
println!("{}", y.get())

drop(y);
// only now will the reference count on the file be decreased
```



## ... make life rue the day it ever decided to hand you lifetimes

@@ Make sure to thank jackh and eddyb





 
 [ICU4X]: https://github.com/unicode-org/icu4x
 [`serde`]: https://docs.rs/serde
 [`rkyv`]: https://docs.rs/rkyv
 [`yoke`]: https://docs.rs/yoke
 [`Cow<'a, T>`]: https://doc.rust-lang.org/stable/std/borrow/struct.Cow.html
 [`Rc<T>`]: https://doc.rust-lang.org/stable/std/rc/struct.Rc.html
 [Shane]: https://github.com/sffc
 [part 2]: https://@@@@

 [^1]: A _locale_ is typically a language and location, though it may contain additional information like the writing system or even things like the calendar system in use.
 [^2]: Bear in mind, this isn't just a matter of picking a format like MM-DD-YYYY! Dates in just US English can look like `4/10/22` or `4/10/2022` or `April 10, 2022`, or `Sunday, April 10, 2022 C.E.`, or `Sun, Apr 10, 2022`, and that's not without thinking about week numbers, quarters, or time! This quickly adds up to a decent amount of data for each locale.



