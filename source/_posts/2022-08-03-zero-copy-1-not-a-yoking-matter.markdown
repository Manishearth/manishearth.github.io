---
layout: post
title: "Not a Yoking Matter (Zero-Copy #1)"
date: 2022-08-03 15:53:33 -0700
comments: true
categories: ["mozilla", "programming", "rust"]
---


_This is part 1 of a three-part series on interesting abstractions for zero-copy deserialization I've been working on over the last year. This part is about making zero-copy deserialization more pleasant to work with. Part 2 is about making it work for more types and can be found [here][part 2]; while Part 3 is about eliminating the deserialization step entirely and can be found [here][part 3]. The posts can be read in any order, though this post contains an explanation of what zero-copy deserialization_ is.


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
    rust_files_written: Vec<String>,
}
```

A typical binary data format will probably store this as a byte for the age, followed by the length of `name`, followed by the bytes for `name`, followed by another length for the vector, followed by a length and string data for each `String` value. Deserializing the `u8` age just involves reading it, but the other two fields require allocating sufficient memory and copying each byte over, in addition to any validation the types may need.

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

You may notice that `rust_files_written` can't be found in this new struct. This is because [`serde`], out of the box, can't handle zero-copy deserialization for anything other than `str` and `[u8]`, for very good reasons. Other frameworks like [`rkyv`] can, however we've also managed to make this possible with [`serde`]. I'll go in more depth about said reasons and our solution in [part 2].


 [`serde`]: https://docs.rs/serde
 [`rkyv`]: https://docs.rs/rkyv
 [part 2]: ../zero-copy-2-zero-copy-all-the-things/

{% endaside %}

{% discussion pion-nought %} Aren't there still copies occurring here with the `age` field? {% enddiscussion %}

Yes, "zero-copy" is somewhat of a misnomer, what it really means is "zero allocations", or, alternatively, "zero large copies". Look at it this way: data like `age` does get copied, but without, say, allocating a vector of `Person<'a>`, you're only going to see that copy occur a couple times when individually deserializing `Person<'a>`s or when deserializing some struct that contains `Person<'a>` a couple times. To have a large copy occur _without_ involving allocations, your type would have to be something that is that large on the stack in the first place, which people avoid in general because it means a large copy every time you move the value around even when you're not deserializing.

## When life gives you lifetimes ....

Zero-copy deserialization in Rust has one very pesky downside: the lifetimes. Suddenly, all of your deserialized types have lifetimes on them. Of course they would; they're no longer self-contained, instead containing references to the data they were originally deserialized from!

This isn't a problem unique to Rust, either, zero-copy deserialization always introduces more complex dependencies between your types, and different frameworks handle this differently; from leaving management of the lifetimes to the user to using reference counting or a GC to ensure the data sticks around. Rust serialization libraries can do stuff like this if they wish, too. In this case, [`serde`], in a very Rusty fashion, wants the library user to have control over the precise memory management here and surfaces this problem as a lifetime.


Unfortunately, lifetimes like these tend to make their way into everything. Every type holding onto your deserialized type needs a lifetime now and it's likely going to become your users' problem too.

Furthermore, Rust lifetimes are a purely compile-time construct. If your value is of a type with a lifetime, you need to know at compile time by when it will definitely no longer be in use, and you need to hold on to its source data until then. Rust's design means that you don't need to worry about getting this _wrong_, since the compiler will catch you, but you still need to _do it_.

All of this isn't ideal for cases where you want to manage the lifetimes at runtime, e.g. if your data is being deserialized from a larger file and you wish to cache the loaded file as long as data deserialized from it is still around.

Typically in such cases you can use [`Rc<T>`], which is effectively the "runtime instead of compile time" version of `&'a T`s safe shared reference, but this only works for cases where you're sharing homogenous types, whereas in this case we're attempting to share different types deserialized from one blob of data, which itself is of a different type.

ICU4X would like users to be able to make use of caching and other data management strategies as needed, so this won't do at all. For a while ICU4X had not one but _two_ pervasive lifetimes threaded throughout most of its types: it was both confusing and not in line with our goals.

## ... make life take the lifetimes back

_A lot of the design here can be found explained in the [design doc]_

After [a bunch of discussion][yoke-discussion] on this, primarily with [Shane], I designed [`yoke`], a crate that attempts to provide _lifetime erasure_ in Rust via self-referential types.

{% discussion pion-nought %} Wait, _lifetime_ erasure? {% enddiscussion %}

Like type erasure! "Type erasure" (in Rust, done using `dyn Trait`) lets you take a compile time concept (the type of a value) and move it into something that can be decided at runtime. Analogously, the core value proposition of `yoke` is to take types burdened with the compile time concept of lifetimes and allow you to decide they be decided at runtime anyway.

{% discussion pion-nought %} Doesn't `Rc<T>` already let you make lifetimes a runtime decision? {% enddiscussion %}

Kind of, `Rc<T>` on its own lets you _avoid_ compile-time lifetimes, whereas `Yoke` works with situations where there is already a lifetime (e.g. due to zero copy deserialization) that you want to paper over.

{% discussion pion-nought %} Cool! What does that look like? {% enddiscussion %}

The general idea is that you can take a zero-copy deserializeable type like a `Cow<'a, str>` (or something more complicated) and "yoke" it to the value it was deserialized from, which we call a "cart".

{% discussion pion-minus%}_\*groan\*_ not another crate named with a pun, Manish. {% enddiscussion %}

I will never stop.

Anyway, here's what that looks like.

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

{% aside issue %}

Some of the APIs here may not quite work due to current compiler bugs. In this blog post I'm using the ideal version of these APIs for illustrative purposes, but it's worth checking with the Yoke docs to see if you may need to use an alternate workaround API. _Most_ of the bugs have been fixed as of Rust 1.61.

{% endaside %}

{% discussion pion-plus %} The example above uses [`postcard`]: `postcard` is a really neat `serde`-compatible binary serialization format, designed for use on resource constrained environments. It's quite fast and has a low codesize, check it out!

 [`postcard`]: https://docs.rs/postcard
{%enddiscussion%}

The type `Yoke<Cow<'static, str>, Rc<[u8]>>` is "a lifetime-erased `Cow<str>` 'yoked' to a backing data store 'cart' that is an `Rc<[u8]>`". What this means is that the Cow contains references to data from the cart, however, the `Yoke` will hold on to the cart type until it is done, which ensures the references from the `Cow` no longer dangle.

Most operations on the data within a `Yoke` operate via `.get()`, which in this case will return a `Cow<'a, str>`, where `'a` is the lifetime of borrow of `.get()`. This keeps things safe: a `Cow<'static, str>` is not really safe to distribute in this case since `Cow` is not actually borrowing from static data; however it's fine as long as we transform the lifetime to something shorter during accesses.

Turns out, the `'static` found in `Yoke` types is actually a lie! Rust doesn't really let you work with types with borrowed content without mentioning _some_ lifetime, and here we want to relieve the compiler from its duty of managing lifetimes and manage them ourselves, so we need to give it _something_ so that we can name the type, and `'static` is the only preexisting named lifetime in Rust.

The actual signature of `.get()` is [a bit weird][Yoke::get] since it needs to be generic, but if our borrowed type is `Foo<'a>`, then the signature of `.get()` is something like this:

```rust
impl Yoke<Foo<'static>> {
    fn get<'a>(&'a self) -> &'a Foo<'a> {
        ...
    }
}
```


For a type to be allowed within a `Yoke<Y, C>`, it must implement `Yokeable<'a>`. This trait is unsafe to manually implement, in most cases you should autoderive it with `#[derive(Yokeable)]`:

```rust
#[derive(Yokeable, Serialize, Deserialize)]
struct Person<'a> {
    age: u8,
    #[serde(borrow)]
    name: Cow<'a, str>,
}

let person: Yoke<Person<'static>, Rc<[u8]> = Yoke::attach_to_cart(file.clone(), |contents| {
    postcard::from_bytes(&contents)
});
```

Unlike most `#[derive]`s, `Yokeable` can be derived even if the fields do not already implement `Yokeable`, except for cases when fields with lifetimes also have other generic parameters. In such cases it typically suffices to tag the type with `#[yoke(prove_covariance_manually)]` and ensure any fields with lifetimes also implement `Yokeable`.


There's a bunch more you can do with `Yoke`, for example you can "project" a yoke to get a new yoke with a subset of the data found in the initial one:

```rust
let person: Yoke<Person<'static>, Rc<[u8]>> = ....;

let person_name: Yoke<Cow<'static, str> = person.project(|p, _| p.name);

```

This allows one to mix data coming from disparate Yokes.

`Yoke`s are, perhaps surprisingly, _mutable_ as well! They are, after all, primarily intended to be used with copy-on-write data, so there are ways to mutate them provided that no _additional_ borrowed data sneaks in:

```rust
let person: Yoke<Person<'static>, Rc<[u8]>> = ....;

// make the name sound fancier
person.with_mut(|person| {
    // this will convert the `Cow` into owned one
    person.name.to_mut().push(", Esq.")
})
```

Overall `Yoke` is a pretty powerful abstraction, useful for a host of situations involving zero-copy deserialization as well as other cases involving heavy borrowing. In ICU4X the abstractions we use to load data always use `Yoke`s, allowing various data loading strategies — including caching — to be mixed


### How it works

{% discussion pion-plus %} Manish is about to say the word "covariant" so I'm going to get ahead of him and say: If you have trouble understanding this and the next section, don't worry! The internal workings of his crate rely on multiple niche concepts that most Rustaceans never need to care about, even those working on otherwise advanced code. {% enddiscussion %}

`Yoke` works by relying on the concept of a _covariant lifetime_. The [`Yokeable`] trait looks like this:

```rust
pub unsafe trait Yokeable<'a>: 'static {
    type Output: 'a;
    // methods omitted
}
```

and a typical implementation would look something like this:

```rust
unsafe impl<'a> Yokeable<'a> for Cow<'static, str> {
    type Output: 'a = Cow<'a, str>;
    // ...
}
```

An implementation of this trait will be implemented on the `'static` version of a type with a lifetime (which I will call `Self<'static>`[^3] in this post), and maps the type to a version of it with a lifetime (`Self<'a>`). It must only be implemented on types where the lifetime `'a` is _covariant_, i.e., where it's safe to treat `Self<'a>` with `Self<'b>` when `'b` is a shorter lifetime. Most types with lifetimes fall in this category[^4], especially in the space of zero-copy deserialization.

{% discussion pion-plus %}You can read more about variance in the [nomicon][nomicon-subtyping]! 

 [nomicon-subtyping]: https://doc.rust-lang.org/nomicon/subtyping.html
{% enddiscussion %}

For any `Yokeable` type `Foo<'static>`, you can obtain the version of that type with a lifetime `'a` with `<Foo as Yokeable<'a>>::Output`. The `Yokeable` trait exposes some methods that allow one to safely carry out the various transforms that are allowed on a type with a covariant lifetime.


`#[derive(Yokeable)]`, in most cases, relies on the compiler's ability to determine if a lifetime is covariant, and doesn't actually generate much code! In most cases, the bodies of the various functions on `Yokeable` are pure safe code, looking like this:

```rust
impl<'a> Yokeable for Foo<'static> {
    type Output: 'a = Foo<'a>;
    fn transform(&self) -> &Self::Output {
        self
    }
    fn transform_owned(self) -> Self::Output {
        self
    }
    fn transform_mut<F>(&'a mut self, f: F)
    where
        F: 'static + for<'b> FnOnce(&'b mut Self::Output) {
        f(self)
    }
    // fn make() omitted since it's not as relevant
}
```

The compiler knows these are safe because it knows that the type is covariant, and the `Yokeable` trait allows us to talk about types where these operations are safe, _generically_.


{% discussion pion-plus%} In other words, there's a certain useful property about lifetime "stretchiness" that the compiler knows about, and we can check that the property applies to a type by generating code that the compiler would refuse to compile if the property did not apply. {% enddiscussion %}

Using this trait, `Yoke` then works by storing `Self<'static>` and transforming it to a shorter, more local lifetime before handing it out to any consumers, using the methods on `Yokeable` in various ways. Knowing that the lifetime is covariant is what makes it safe to do such lifetime "squeezing". The `'static` is a lie, but it's safe to do that kind of thing as long as the value isn't actually accessed with the `'static` lifetime, and we take great care to ensure it doesn't leak.

## Better conversions: ZeroFrom

A crate that pairs well with this is [`zerofrom`][zerofrom-crate], primarily designed and written by [Shane]. It comes with the [`ZeroFrom`] trait:

```rust
pub trait ZeroFrom<'zf, C: ?Sized>: 'zf {
    fn zero_from(other: &'zf C) -> Self;
}
```

The idea of this trait is to be able to work generically with types convertible to (often zero-copy) borrowed types.

For example, `Cow<'zf, str>` implements both `ZeroFrom<'zf, str>` and `ZeroFrom<'zf, String>`, as well as `ZeroFrom<'zf, Cow<'a, str>>`. It's similar to the [`AsRef`] trait but it allows for more flexibility on the kinds of borrowing occuring, and implementors are supposed to minimize the amount of copying during such a conversion. For example, when `ZeroFrom`-constructing a `Cow<'zf, str>` from some other `Cow<'a, str>`, it will _always_ construct a `Cow::Borrowed`, even if the original `Cow<'a, str>` were owned.

`Yoke` has a convenient constructor [`Yoke::attach_to_zero_copy_cart()`][yoke-attach] that can create a `Yoke<Y, C>` out of a cart type `C` if `Y<'zf>` implements `ZeroFrom<'zf, C>` for all lifetimes `'zf`. This is useful for cases where you want to do basic self-referential types but aren't doing any fancy zero-copy deserialization.


## ... make life rue the day it thought it could give you lifetimes

Life with this crate hasn't been all peachy. We've, uh ... [unfortunately][bug-10] [discovered][bug-1] [a][bug-2] [toweringly][bug-3] [large][bug-4] [pile][bug-5] [of][bug-6] [gnarly][bug-7] [compiler][bug-8] [bugs][bug-9]. A lot of this has its root in the fact that `Yokeable<'a>` in most cases is bound via `for<'a> Yokeable<'a>` ("`Yokeable<'a>` for all possible lifetimes `'a`"). The `for<'a>` is a niche feature known as a higher-ranked lifetime or trait bound (often referred to as "HRTB"), and while it's always been necessary in some capacity for Rust's typesystem to be able to reason about function pointers, it's also always been rather buggy and is often discouraged for usages like this.

We're using it so that we can talk about the lifetime of a type in a generic sense. Fortunately, there is a language feature under active development that will be better suited for this: [Generic Associated Types][GAT].


This feature isn't stable yet, but, fortunately for _us_, most compiler bugs involving `for<'a>` _also_ impact GATs, so we have been benefitting from the GAT work, and a lot of our bug reports have helped shore up the GAT code. Huge shout out to [Jack Huey] for fixing a lot of these bugs, and [eddyb] for helping out in the debugging process.

As of Rust 1.61, a lot of the major bugs have been fixed, however there are still some bugs around trait bounds for which the `yoke` crate maintains some [workaround helpers]. It has been our experience that most compiler bugs here are not _restrictive_ when it comes to what you can do with the crate, but they may end up with code that looks less than ideal. Overall, we still find it worth it, we're able to do some really neat zero-copy stuff in a way that's externally convenient (even if some of the internal code is messy), and we don't have lifetimes everywhere.


## Try it out!

While I don't consider the [`yoke`] crate "done" yet, it's been in use in ICU4X for a year now and I consider it mature enough to recommend to others. Try it out! Let me know what you think!

_Thanks to [Finch](https://twitter.com/plaidfinch), [Jane](https://twitter.com/yaahc_), and [Shane] for reviewing drafts of this post_




 
 [ICU4X]: https://github.com/unicode-org/icu4x
 [`serde`]: https://docs.rs/serde
 [`rkyv`]: https://docs.rs/rkyv
 [`yoke`]: https://docs.rs/yoke
 [zerofrom-crate]: https://docs.rs/zerofrom
 [`ZeroFrom`]: https://docs.rs/zerofrom/latest/zerofrom/trait.ZeroFrom.html
 [yoke-attach]: https://docs.rs/yoke/latest/yoke/struct.Yoke.html#method.attach_to_zero_copy_cart
 [`AsRef`]: https://doc.rust-lang.org/stable/std/convert/trait.AsRef.html
 [`Cow<'a, T>`]: https://doc.rust-lang.org/stable/std/borrow/struct.Cow.html
 [`Rc<T>`]: https://doc.rust-lang.org/stable/std/rc/struct.Rc.html
 [Shane]: https://github.com/sffc
 [Yoke::get]: https://docs.rs/yoke/latest/yoke/struct.Yoke.html#method.get
 [part 2]: ../zero-copy-2-zero-copy-all-the-things/
 [part 3]: ../zero-copy-3-so-zero-its-dot-dot-dot-negative/
 [yoke-discussion]: https://github.com/unicode-org/icu4x/issues/667#issuecomment-828123099
 [design doc]: https://github.com/unicode-org/icu4x/blob/main/utils/yoke/design_doc.md
 [`Yokeable`]: https://docs.rs/yoke/latest/yoke/trait.Yokeable.html
 [bug-1]: https://github.com/rust-lang/rust/issues/86703
 [bug-2]: https://github.com/rust-lang/rust/issues/88446
 [bug-3]: https://github.com/rust-lang/rust/issues/89436
 [bug-4]: https://github.com/rust-lang/rust/issues/89196
 [bug-5]: https://github.com/rust-lang/rust/issues/84937
 [bug-6]: https://github.com/rust-lang/rust/issues/89418
 [bug-7]: https://github.com/rust-lang/rust/issues/90950
 [bug-8]: https://github.com/rust-lang/rust/issues/96223
 [bug-9]: https://github.com/rust-lang/rust/issues/91899
 [bug-10]: https://github.com/rust-lang/rust/issues/90638
 [GAT]: https://rust-lang.github.io/generic-associated-types-initiative/index.html
 [workaround helpers]: https://docs.rs/yoke/latest/yoke/trait_hack/index.html
 [Jack Huey]: https://github.com/jackh726
 [eddyb]: https://github.com/eddyb

 [^1]: A _locale_ is typically a language and location, though it may contain additional information like the writing system or even things like the calendar system in use.
 [^2]: Bear in mind, this isn't just a matter of picking a format like MM-DD-YYYY! Dates in just US English can look like `4/10/22` or `4/10/2022` or `April 10, 2022`, or `Sunday, April 10, 2022 C.E.`, or `Sun, Apr 10, 2022`, and that's not without thinking about week numbers, quarters, or time! This quickly adds up to a decent amount of data for each locale.
 [^3]: This isn't real Rust syntax; since `Self` is always just `Self`, but we need to be able to refer to `Self` as a higher-kinded type in this scenario.
 [^4]: Types that aren't are ones involving mutability (`&mut` or interior mutability) around the lifetime, and ones involving function pointers and trait objects.
 

