---
layout: post
title: "You're doing it wrong"
date: 2017-04-05 09:37:40 -0700
comments: true
categories: programming mozilla
---


"You're doing it wrong"

A common refrain in issue trackers and discussion forums everywhere. In isolation,
it's a variant of RTFM -- give a non-answer when someone wants help, and bounce them
back to a manual or docs which they probably have already read. Not very helpful,
and not useful to anyone. Of course, one can accompany it with a nice explanation
of how to do it right; "You're doing it wrong" isn't always a bad thing :)

Especially when it comes to programming languages, but in general in the context of any programming
tool or library, "you're doing it wrong" is almost always due to a "bad" mental model. The person, whilst
learning, has built a mental model of how the tool works, but this doesn't accurately reflect
reality. Other times, it does reflect reality, but it does not reflect the mental model of the
maintainers (there can be multiple valid ways of looking at something!),
which leads to an impedance mismatch when reading docs or error messages.

In other cases, "doing it wrong" is a [case of the XY problem][xy], where the user has problem X,
and think they can solve it with solution Y, and end up asking how they can achieve Y. This happens pretty
often &mdash; folks may be approaching your technology with prior experience with related things
that work differently, and may think the same idioms apply.

When I was at [WONTFIX], someone who had done support work in the past mentioned that one
thing everyone learns in support is **"the user is always wrong .... and it's not their fault!"**.


 [xy]: https://meta.stackexchange.com/q/66377/178438
 [WONTFIX]: https://maintainerati.org/

This is a pretty good template for an attitude to approach "doing it wrong" questions about your
technology on online forums as well. And this doesn't just benefit the users who ask questions,
this attitude can benefit your technology!

Back when I used to be more active contributing to the Rust compiler, I also used to hang out in
`#rust` a lot, and often answer newbie questions (now `#rust-beginners` exists too, and I hang out
in both, but I don't really actively participate as much). One thing I learned to do was probe
deeper into why people hit that confusion in the first place. It's almost always a "bad" mental
model. Rust is rarely the first programming language folks learn, and people approach it with
preconceptions about how programming works. This isn't unique to Rust, this happens any time someone
learns a language with a different paradigm &mdash; learning C or C++ after doing a GCd language,
learning a functional language after an imperative one, statically typed after dynamic, or one of
the many other axes by which programming languages differ.

Other times, it's just assumptions they made when reading between the lines of whatever resource
they used to learn the language.

So, anyway, folks often have a "bad" mental model. If we are able to identify that model and correct
it, we have saved that person from potentially getting confused at every step in the future. Great!

With a _tiny_ bit more effort, however, we can do one step better. Not for that person, but for
ourselves! We can probe a bit more and try to understand what caused them to obtain that mental
model. And fix the docs so that it never happens again! Of course, not everyone reads the docs, but
that's what diagnostics are for (in the case of errors). They're a tool to help us nudge the user
towards the right mental model, whilst helping them fix their immediate problem. Rust has for a long
time had pretty great diagnostics, with improvements happening all the time[^1]. I think this is at
least in part due to the attitude of the folks in `#rust`; always trying to figure out how to
preempt various confusions they see.

It's a good attitude to have. I hope more folks, both in and out of the Rust community, approach
"You're doing it wrong" cases like that.


 [^1]: Diagnostics issues are often the easiest way to contribute to the compiler itself, so if you want to contribute, I suggest starting there. Willing to mentor!