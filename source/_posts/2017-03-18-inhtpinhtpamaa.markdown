---
layout: post
title: "I Never Hear The Phrase 'INHTPAMA' Anymore"
date: 2017-03-18 19:50:42 -0700
comments: true
categories: programming mozilla rust tidbits
---

Imagine never hearing the phrase 'INHTPAMA' again.

Oh, that's already the case? Bummer.

Often, when talking about Rust, folks refer to the core aliasing rule as "that `&mut` thing",
"compile-time `RWLock`" (or "compile-time `RefCell`"), or something similar. Basically, referring to
the fact that you can't mutate the data that is currently held via an `&` reference, and that you
can't mutate or read the data currently held via an `&mut` reference except through that reference
itself.

It's always bugged me that we really don't have a name for this thing. It's one of the core
bits of Rust, and crops up often in discussions.

But we did have a name for it! It was "INHTPAMA" (which was later butchered into "INHTWAMA").

This is a reference to [Niko's 2012 blog post][inhtpama], titled
"Imagine Never Hearing The Phrase 'aliasable, mutable' again". It's where the aliasing
rules came from. Go read it, it's great. It talks about this weird language with at symbols
and purity, but I assure you, that language is Baby Rust. Or maybe Teenage Rust. The
[lifecycle of rusts is complex and interesting][rusts] and I don't know how to categorize it.

The point of this post isn't really to encourage reviving the use of "INHTWAMA"; it's
a rather weird acronym that will probably confuse folks. I would like to have a better
way of refering to "that `&mut` thing", but I'd prefer if it wasn't a confusing acronym
that carries no meaning of its own if you don't know the history of it. That's a recipe for
making new community members feel like outsiders.

But that post is amazing and I'd hate to see it drop out of the collective
memory of the Rust community.

 [inhtpama]: http://smallcultfollowing.com/babysteps/blog/2012/11/18/imagine-never-hearing-the-phrase-aliasable/
 [rusts]: https://www.ars.usda.gov/images/docs/9910_10104/Pg-lifecycle.jpg
