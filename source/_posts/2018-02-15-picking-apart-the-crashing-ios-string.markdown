---
layout: post
title: "Picking apart the crashing iOS string"
date: 2018-02-15 08:49:07 -0800
comments: true
categories: programming unicode
---

So there's [yet another iOS text crash][article], where just looking at a particular string crashes
iOS. Basically, if you put this string in any system text box (and other places), it crashes that
process. I've been testing it by copy-pasting characters into Spotlight so I don't end up crashing
my browser.

The original sequence is U+0C1C U+0C4D U+0C1E U+200C U+0C3E, which is a sequence of Telugu
characters: the consonant ja (జ), a virama (&#xA0;్&#xA0;), the consonant nya (ఞ), a zero-width non-joiner, and
the vowel aa (&#xA0;ా).

I was pretty interested in what made this sequence "special", and started investigating.


So first when looking into this, I thought that the &lt;ja, virama, nya&gt; sequence was the culprit.
That sequence forms a special ligature in many Indic scripts (ज्ञ in Devanagari) which is often
considered a letter of its own. However, the ligature for Telugu doesn't seem very "special".

Also, from some experimentation, this bug seemed to occur for _any_ pair of Telugu consonants with
a vowel, as long as the vowel is not &#xA0;ై (ai). Huh.

The ZWNJ must be doing something weird, then. &lt;consonant, virama, consonant, vowel&gt; is a
pretty common sequence in any Indic script; but ZWNJ before a vowel isn't very useful for most
scripts (except for Bengali and Oriya, but I'll get to that).

And then I saw that [there was a sequence in Bengali][bengali-tweet] that also crashed.

The sequence is U+09B8 U+09CD U+09B0 U+200C U+09C1, which is the consonant "so" (স), a virama (&#xA0;্&#xA0;),
the consonant "ro" (র), a ZWNJ, and vowel u (&nbsp;&#xA0;ু).

Before we get too into this, let's first take a little detour to learn how Indic scripts work:


 [article]: https://www.theverge.com/2018/2/15/17015654/apple-iphone-crash-ios-11-bug-imessage
 [bengali-tweet]: https://twitter.com/FakeUnicode/status/963300865762254848

## Indic scripts and consonant clusters

Indic scripts are _abugidas_; which means that their "letters" are consonants, which you
can attach diacritics to to change the vowel. By default, consonants have a base vowel.
So, for example, क is "kuh" (kə, often transcribed as "ka"), but I can change the vowel to make it के
(the "ka" in "okay") का ("kaa", like "car").

Usually, the default vowel is the ə sound, though not always (in Bengali it's more of an o sound).

Because of the "default" vowel, you need a way to combine consonants. For example, if you wished to
write the word "ski", you can't write it as स + की (sa + ki = "saki"), you must write it as स्की.
What's happened here is that the स got its vowel "killed", and got tacked on to the की to form a
consonant cluster ligature.

You can _also_ write this as स्&zwnj;की . That little tail you see on the स is known as a "virama";
it basically means "remove this vowel". Explicit viramas are sometimes used when there's no easy way
to form a ligature, e.g. in ङ्&zwnj;ठ because there is no simple way to ligatureify ङ into ठ. Some scripts
also _prefer_ explicit viramas, e.g. "ski" in Malayalam is written as സ്കീ, where the little crescent
is the explicit virama.

In unicode, the virama character is always used to form a consonant cluster. So स्की was written as
&lt;स, &#xA0;्, क, &#xA0;ी&gt;, or &lt;sa, virama, ka, i&gt;. If the font supports the cluster, it will show up
as a ligature, otherwise it will use an explicit virama.


For Devanagari and Bengali, _usually_, in a consonant cluster the first consonant is munged a bit and the second consonant stays intact.
There are exceptions -- sometimes they'll form an entirely new glyph (क + ष = क्ष), and sometimes both
glyphs will change (ड + ड = ड्ड, द + म = द्म, द + ब = द्ब). Those last ones should look like this in conjunct form:

{% img center /images/post/unicode-crash/conjuncts.png 200 %}

## Investigating the Bengali case

Now, interestingly, unlike the Telugu crash, the Bengali crash seemed to only occur when the second
consonant is র ("ro"). However, I can trigger it for any choice of the first consonant or vowel, except
when the vowel is &#xA0;ো (o) or &#xA0;ৌ (au).

Now, র is an interesting consonant in some Indic scripts, including Devanagari. In Devanagari,
it looks like र ("ra"). However, it does all kinds of things when forming a cluster. If you're having it
precede another consonant in a cluster, it forms a little feather-like stroke, like in र्क (rka). In Marathi,
that stroke can also look like a tusk, as in र्&zwj;क. As a suffix consonant, it can provide a little
"extra leg", as in क्र (kra). For letters without a vertical stroke, like ठ (tha), it does this caret-like thing,
ठ्र (thra).

Basically, while most consonants retain some of their form when put inside a cluster, र does not. And
a more special thing about र is that this happens even when र is the _second_ consonant in a cluster -- as I mentioned
before, for most consonant clusters the second consonant stays intact. While there are exceptions, they are usually
specific to the cluster; it is only र for which this happens for all clusters.

It's similar in Bengali, র as the second consonant adds a tentacle-like thing on the existing consonant. For example,
প + র (po + ro) gives প্র (pro).

But it's not just র that does this in Bengali, the consonant "jo" does as well. প + য (po + jo) forms প্য (pjo),
and the য is transformed into a wavy line called a "jophola".

So I tried it with য  &mdash; , and it turns out that the Bengali crash occurs for  য as well!
So the general Bengali case is &lt;consonant, virama, র OR য, ZWNJ, vowel&gt;, where the vowel is not  &#xA0;ো or &#xA0;ৌ.

## Suffix-joining consonants

So we're getting close, here. At least for Bengali, it occurs when the second consonant is such that it often
combines with the first consonant without modifying its form much.

In fact, this is the case for Telugu as well! Consonant clusters in Telugu are usually formed by preserving the
original consonant, and tacking the second consonant on below!

For example, the original crashy string contains the cluster జ + ఞ, which looks like జ్ఞ. The first letter isn't
really modified, but the second is.

From this, we can guess that it will also occur for Devanagari with र. Indeed it does! U+0915 U+094D U+0930 U+200C U+093E, that is,
&lt;क, &#xA0;्, र, zwnj, ा&gt; (&lt; ka, virama, ra, zwnj, aa &gt;) is one such crashing sequence.

But this isn't really the whole story, is it? For example, the crash does occur for "kro" + zwnj + vowel in Bengali,
and in "kro" (ক্র = ক + র = ko + ro) the resultant cluster involves the munging of both the prefix and suffix. But
the crash doesn't occur for द्ब or ड्ड. It seems to be specific to the letter, not the nature of the cluster.

Digging deeper, the reason is that for many fonts (presumably the ones in use), these consonants
form "suffix joining consonants" (a term I made up) when preceded by a virama

For example, the sequence virama + क gives &nbsp;&#xA0;्क, i.e. it renders a virama with a placeholder followed by a क.

But, for र, virama + र renders &#xA0;्र, which for me looks like this:

{% img center /images/post/unicode-crash/virama-ra.png 200 %}

In fact, this is the case for the other consonants as well. For me, &#xA0;्र &#xA0;্র &#xA0;্য &#xA0;్ఞ &#xA0;్క
(Devanagari virama-ra, Bengali virama-ro, Bengali virama-jo, Telugu virama-nya, Telugu virama-ka)
all render as "suffix joining consonants":

{% img center /images/post/unicode-crash/virama-consonant.png 200 %}

(This is true for all Telugu consonants, not just the ones listed).

An interesting bit is that the crash does not occur for &lt;र, virama, र, zwnj, vowel&gt;, because र-virama-र
uses the prefix-joining form of the first र (र्र). The same occurs for র with itself or ৰ. Because the virama
is "sticker" to the left in these cases, it doesn't cause a crash. (h/t [hackbunny] for discovering this
using a [script][viramarama] to enumerate all cases).
 
Kannada _also_ has "suffix joining consonants", but for some reason I cannot trigger the crash with it.

 [hackbunny]: https://github.com/hackbunny
 [viramarama]: https://github.com/hackbunny/viramarama

## The ZWNJ

The ZWNJ is curious. The crash doesn't happen without it, but as I mentioned before a ZWNJ before a vowel
doesn't really _do_ anything for most Indic scripts. In Indic scripts, a ZWNJ can be used to explicitly force a
virama if used after the virama (I used it to write स्&zwnj;की in this post), however that's not how it's being used here.

In Bengali and Oriya specifically, a ZWNJ can be used to force a different vowel form when used before a vowel
(e.g. রু vs র&zwnj;ু), however this bug seems to apply to vowels for which there is only one form, and this bug
also applies to other scripts where this isn't the case anyway.


## Generalizing

So, ultimately, the full set of cases that cause the crash are:

Any sequence `<consonant1, virama, consonant2, ZWNJ, vowel>` in Devanagari, Bengali, and Telugu, where:

 - `consonant2` is suffix-joining -- i.e. र, র, য, and all Telugu consonants
 - If `consonant2` is  र or র, `consonant1` is not the same letter (or a variant, like ৰ)
 - `vowel` is not &#xA0;ై or &#xA0;ৌ

This leaves some questions open:

Why doesn't it apply to Kannada? Or, for that matter, Khmer, which has a similar virama-like thing called a "coeng".
What's up with the exception vowels in Bengali and Telugu?


## Conclusion

I don't really have _one_ guess as to what's going on here -- I'd love to see what people think -- but my current
guess is that the "affinity" of the virama to the left instead of the right confuses the algorithm that handles ZWNJs after
viramas into thinking the ZWNJ applies to the virama (it doesn't, there's a consonant in between), and this leads to some numbers
not matching up and causing a buffer overflow or something.

An interesting thing is that I can cause this crash to happen more reliably in browsers by clicking on the string.

Additionally, _sometimes_ it actually renders in spotlight for a split second before crashing; which means that either
the crash isn't deterministic, or it occurs in some process _after_ rendering. I'm not sure what to think of either.

I'd love to hear if folks have further insight into this.

<small>Yes, I could attach a debugger to the crashing process and investigate that instead, but that's no fun 😂</small>