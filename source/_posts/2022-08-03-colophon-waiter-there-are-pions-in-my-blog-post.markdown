---
layout: post
title: "Colophon: Waiter, There Are Pions in my Blog Post!"
date: 2022-08-03 09:43:49 -0700
comments: true
categories: ["meta", "writing", "physics"]
---


I've added a couple new styling elements to my blog and I make use of them extensively in upcoming posts, I thought I'd talk a bit about them because I expect people will have questions.

The main thing is that I have nice aside styling.

{% aside example %}

Asides are things that look like _this_.

{% endaside %}

The actual color scheme comes from the asides used in [bikeshed], the tool used to generate Web specifications and C++ spec proposals. I edit a couple [WebXR](https://immersive-web.github.io/webxr/) specs and used to read specs very often when I worked on browsers; I like the styling they use.

{% aside note %}

I also think it's kinda funny to get readers do a double-take when they see familiar styling out of context.

{% endaside %}

Besides the "example" and "note" ones shown above, there's also an "issue" one.

{% aside issue %}

Figure out a way to include an example of an "issue" aside in this post that works in context like the "note" and "example" ones.

{% endaside %}

These asides are useful for calling out supplemental information; and add to my existing repertoire of footnotes, em dashes, semicolons, and parentheses as a nonlinear writing tool.

{% discussion pion-minus %}

Manish, you're burying the lede.

{% enddiscussion %}

Oh, right. Fine. The pions.

I've also introduced three similarly styled "character discussion" asides that show a discussion with a [pion]. There's a "positive" one that's generally helpful, a "negative" one that's grumpy, and a "confused" (neutrally charged) one that asks questions.

Having little characters participate in the blog post works really well; it gives a sense of _flow_ to the articles. I'm also hoping it makes them easier to read, breaking up otherwise dense technical content with lighter conversational content[^5]. Asking questions through them give the reader an anchor point for themselves if they're similarly confused, without me making any assumption that the reader did or didn't understand a part.

They're also _yet another_ way for me to write nonlinearly, and I _love_ writing nonlinearly.

Adding interlocutors to my blog was extremely inspired by other people: [Amos] has Cool Bear, and [Xe] has [Mara][xe-mara], both of which serve similar purposes. While [Alex] doesn't quite have interlocutors, their use of [ISO 7010] icons for asides gave me the idea to use something relevant to my interests while picking characters.

{% discussion pion-confused %}

Okay but why pions? Scratch that, _what_ is a pion?

{% enddiscussion %}

You're a pion!

{% discussion pion-confused %}

You know what I meant!

{% enddiscussion %}

Okay, okay.

So a [pion] is a type of subatomic particle, and is part of the mechanism holding the nucleus of an atom together. There are three of them, π<sup>0</sup> , π<sup>+</sup> , and π<sup>−</sup>, with the positive and negative ones being antiparticles of each other.

As for _why_ I've chosen that particle in particular, explaining that requires some history first.

Back when we only knew about protons, neutrons, and electrons, physicists were attempting to figure out how atomic nuclei stay together. They're made of protons and neutrons, which means they're just a lot of positively and neutrally changed thingies crammed into a tight space. There's not much reason for that to want to stay together, but there's plenty of reason for it to come apart. This is rather concerning to beings made out of atoms, like physicists.

To resolve this, physicists theorized the existence of the pion[^1], a type of particle that is exchanged between protons and neutrons in the nucleus and forms a mechanism for carrying force.

{% discussion pion-plus %}
_Why_ "exchanging particles" works to carry force is a complicated topic (and "exchanging particles" is a very simplistic characterization) that would be very hard to explain here, but you can read up on "force carriers" in quantum field theory if you're interested.

A useful example is that photons are force carriers for the electromagnetic force, which is why you can make radio waves (made up of photons) by messing with electromagnetic fields.
{% enddiscussion %}


And when physicists think there's a new particle, of course they go looking for it. And they did!


... but they found something else entirely.

Bear in mind, this was not the heyday of particle discovery when there was a new particle being discovered every Tuesday. Physicists knew about protons, neutrons, electrons, and probably pions, and were justifiably surprised when a completely different particle came knocking. Instead of having the properties they expected for the pion, it was basically like a heavier electron.

The physicist I. I. Rabi famously remarked "Who ordered that?" when they figured out what had happened. There was no _reason_ for such a particle to exist, they had this nice consistent model of the atom that needed four kinds of particle and they found this fifth one just floating around, not really _doing_ anything.

This particle was the [muon], and this story is why I use a Greek μ as my avatar everywhere[^2]. Given this history, the pion feels like a very natural choice as a foil in blog posts I write.

Furthermore, there are three of them, which lets me use them for different purposes! One for "positive" commentary, one for "negative" commentary, and a third "confused" one for questions.

{% discussion pion-plus %}

The neutral pion being "confused" actually works really well because while π<sup>+</sup> (and π<sup>−</sup>) have straightforward [quark] representations of an up and antidown quark (and a down and an antiup quark for π<sup>−</sup>), π<sup>0</sup> is a superposition between either an up and antiup quark or a down and antidown quark.

 [quark]: https://en.wikipedia.org/wiki/Quark
{% enddiscussion %}



<br>


I can't wait for people to get to see more of these in my upcoming posts; I really enjoyed writing with them!

{% discussion pion-confused %}

One last question, are these supposed to be three characters or one character with different moods?

{% enddiscussion %}

[You tell me][one-electron].


 [bikeshed]: https://tabatkins.github.io/bikeshed/
 [pion]: https://en.wikipedia.org/wiki/Pion
 [muon]: https://en.wikipedia.org/wiki/Muon
 [Amos]: https://fasterthanli.me/articles
 [Alex]: https://myrrlyn.net/blog
 [Xe]: https://xeiaso.net/blog/
 [xe-mara]: https://xeiaso.net/blog/how-mara-works-2020-09-30
 [ISO 7010]: https://en.wikipedia.org/wiki/ISO_7010
 [one-electron]: https://en.wikipedia.org/wiki/One-electron_universe
 [^1]: At the time, they called them "mesons", which is currently the name of a general class of particles which pions belong to.
 [^2]: My name starting with an M and my interest in writing systems is a _part_ of it, but the main reason is that I really like this story and this kind of thing is what got me into physics in the first place.
 [^5]: I'm reminded of how a lot of people don't enjoy reading Tolkien because he spends pages describing, like, one tree, as opposed to most fiction which has plenty of conversational content. Nonfiction books (and blog posts) have the wall-of-description property _by default_ so spending time on improving this makes a lot of sense to me.