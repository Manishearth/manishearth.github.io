---
layout: post
title: "Let's stop ascribing meaning to code points"
date: 2017-01-14 10:13:18 -0800
comments: true
categories: programming
---

_Update: This post got a sequel, [Breaking our latin-1 assumptions][breakl1]._

I've seen misconceptions about Unicode crop up regularly in posts discussing it. One very common
misconception I've seen is that _code points have cross-language intrinsic meaning_.

It usually comes up when people are comparing UTF8 and UTF32. Folks start implying that code points
_mean_ something, and that O(1) indexing or slicing at code point boundaries is a useful operation.
I've also seen this assumption manifest itself in actual programs which make incorrect assumptions
about the nature of code points and mess things up when fed non-Latin text.


If you like reading about unicode, you might also want to go through [Eevee's article][vee]
on the dark corners of unicode. Great read!

 [vee]: https://eev.ee/blog/2015/09/12/dark-corners-of-unicode/
 [breakl1]: http://manishearth.github.io/blog/2017/01/15/breaking-our-latin-1-assumptions/

## Encodings

So, anyway, we have some popular encodings for Unicode. UTF8 encodes 7-bit code points as a single
byte, 11-bit code points as two bytes, 16-bit code points as 3 bytes, and 21-bit code points as four
bytes. UTF-16 encodes the first three in two bytes, and the last one as four bytes (logically, a
pair of two-byte code units). UTF-32 encodes all code points as 4-byte code units. UTF-16 is mostly
a "worst of both worlds" compromise at this point, and the main programming language I can think of
that uses it (and exposes it in this form) is Javascript, and that too in a broken way.

The nice thing about UTF8 is that it saves space. Of course, that is subjective and dependent on
the script you use most commonly, for example my first name is 12 bytes in UTF-8 but only 4
in ISCII (or a hypothetical unicode-based encoding that swapped the Devanagri Unicode block with
the ASCII block). It also uses more space over the very non-hypothetical UTF-16 encoding if you
tend to use code points in the U+0800 - U+FFFF range. It always uses less space than UTF-32 however.

A commonly touted disadvantage of UTF-8 is that string indexing is `O(n)`. Because code points take
up a variable number of bytes, you won't know where the 5th codepoint is until you scan the string
and look for it. UTF-32 doesn't have this problem; it's always `4 * index` bytes away.

The problem here is that indexing by code point shouldn't be an operation you ever need!


## Indexing by code point

The main time you want to be able to index by code point is if you're implementing algorithms
defined in the unicode spec that operate on unicode strings (casefolding, segmentation, NFD/NFC).
Most if not all of these algorithms operate on whole strings, so implementing them
as an iteration pass is usually necessary anyway, so you don't lose anything if you can't
do arbitrary code point indexing.

But for application logic, dealing with code points doesn't really make sense. This is because
code points have no intrinsic meaning. They are not "characters". I'm using scare quotes here
because a "character" isn't a well-defined concept either, but we'll get to that later.

For example, "e&#x0301;" is two code points (`e` +` ́`), where one of them is a combining accent. My name,
"मनीष", visually looks like three "characters", but is four code points. The "नी" is made up of `न`
+ `ी`. My last name contains a "character" made up of three code points (and multiple two-code-point
"characters"). The flag emoji "🇺🇸" is also made of two code points, `🇺` + `🇸`.


One false assumption that's often made is that code points are a single column wide. They're not.
They sometimes bunch up to form characters that fit in single "columns". This is often dependent on
the font, and if your application relies on this, you should be querying the font. There are even
code points like U+FDFD (﷽) which are often rendered multiple columns wide. In fact, in my
_monospace_ font in my text editor, that character is rendered _almost_ 12 columns wide. Yes,
"almost", subsequent characters get offset a tiny bit. I don't know why.


Another false assumption is that editing actions (selection, backspace, cut, paste) operate on code
points. In both Chrome and Firefox, selection will often include multiple code points. All the
multi-code-point examples I gave above fall into this category. An interesting testcase for this is
the string "ᄀᄀᄀ각ᆨᆨ", which will rarely if ever render as a single "character" but will be considered
as one for the purposes of selection, pretty much universally. I'll get to why this is later.

Backspace can gobble multiple code points at once too, but the heuristics are different. The reason
behind this is that backspace needs to mirror the act of typing, and while typing sometimes
constructs multi-codepoint characters, backspace decomposes it piece by piece. In cases where a
multi-codepoint "character" _can_ be logically decomposed (e.g. "letter + accent"), backspace will
decompose it, by removing the accent or whatever. But some multi-codepoint characters are not
"constructions" of general concepts that should be exposed to the user. For example, a user should
never need to know that the "🇺🇸" flag emoji is made of `🇺` + `🇸`, and hitting backspace on it should
delete both codepoints. Similarly, variation selectors and other such code points shouldn't
be treated as their own unit when backspacing.

On my Mac most builtin apps (which I presume use the OSX UI toolkits) seem to use the same
heuristics that Firefox/Chrome use for selection for both selection and backspace. While the
treatment of code points in editing contexts is not consistent, it seems like applications
consistently do not consider code points as "editing units".


Now, it is true that you often need _some_ way to index a string. For example, if you have a large
document and need to represent a slice of it. This could be a user-selection, or something delimeted
by markup. Basically, you've already gone through the document and have a section you want to be
able to refer to later without copying it out.

However, you don't need code point indexing here, byte
indexing works fine! UTF8 is designed so that you can check if you're on a code point boundary even
if you just byte-index directly. It does this by restricting the kinds of bytes allowed. One-byte
code points never have the high bit set (ASCII). All other code points have the high bit set in each
byte. The first byte of multibyte codepoints always starts with a sequence that specifies the number
of bytes in the codepoint, and such sequences can't be found in the lower-order bytes of any
multibyte codepoint. You can see this visually in the table [here][utf8desc]. The upshot of all this
is that you just need to check the current byte if you want to be sure you're on a codepoint
boundary, and if you receive an arbitrarily byte-sliced string, you will not mistake it for
something else. It's not possible to have a valid code point be a subslice of another, or form a
valid code point by subslicing a sequence of two different ones by cutting each in half.

So all you need to do is keep track of the byte indices, and use them for slicing it later.

All in all, it's important to always remember that "code point" doesn't have intrinsic meaning. If
you need to do a segmentation operation on a string, find out what *exactly* you're looking for, and
what concept maps closest to that. It's rare that "code point" is the concept you're looking for.
In _most_ cases, what you're looking for instead is "grapheme cluster".

 [utf8desc]: https://en.wikipedia.org/wiki/UTF-8#Description


## Grapheme clusters

The concept of a "character" is a nebulous one. Is "&#x1100;&#x1161;&#x11A8;" a single character, or
three? How about "नी"? Or "நி"? Or the "👨‍❤️‍👨" emoji[^1]? Or the "👨‍👨‍👧‍👧" family emoji[^3]?
Different scripts have different concepts which may not clearly map to the Latin notion of "letter"
or our programmery notion of "character".

Unicode itself gives the term ["character"][gloss-char] multiple incompatible meanings, and as
far as I know doesn't use the term in any normative text.

Often, you need to deal with what is actually displayed to the user. A lot of terminal emulators do
this wrong, and end up messing up cursor placement. I used to use irssi-xmpp to keep my Facebook and
Gchat conversations in my IRC client, but I eventually stopped as I was increasingly chatting in
Marathi or Hindi and I prefer using the actual script over romanizing[^5], and it would just break
my terminal[^2]. Also, they got rid of the XMPP bridge but I'd already cut down on it by then.

So sometimes, you need an API querying what the font is doing. Generally, when talking about the
actual rendered image, the term "glyph" or "glyph image" is used.

However, you can't always query the font. Text itself exists independent of rendering, and sometimes
you need a rendering-agnostic way of segmenting it into "characters".

For this, Unicode has a concept of ["grapheme cluster"][gloss-gc]. There's also "extended grapheme
cluster" (EGC), which is basically an updated version of the concept. In this post, whenever
I use the term "grapheme cluster", I am talking about EGCs.

The term is defined and explored in [UAX #29]. It starts by pinning down the still-nebulous
concept of "user-perceived character" ("a basic unit of a writing system for a language"),
and then declares the concept of a "grapheme cluster" to be an approximation to this notion
that we can determine programmatically.

A rough definition of grapheme cluster is a "horizontally segmentable unit of text".

The spec goes into detail as to the exact algorithm that segments text at grapheme cluster
boundaries. All of the examples I gave in the first paragraph of this section are single grapheme
clusters. So is "ᄀᄀᄀ각ᆨᆨ" (or "ᄀᄀᄀ&#x1100;&#x1161;&#x11A8;ᆨᆨ"), which apparently is considered a
single syllable block in Hangul even though it is not of the typical form of leading consonant +
vowel + optional tail consonant, but is not something you'd see in modern Korean. The spec
explicitly talks of this case so it seems to be on purpose. I like this string because nothing I
know of renders it as a single glyph; so you can easily use it to tell if a particular segmentation-
aware operation uses grapheme clusters as segmentation. If you try and select it, in most browsers
you will be forced to select the whole thing, but backspace will delete the jamos one by one. For
the second string, backspace will decompose the core syllable block too (in the first string the
syllable block &#x1100;&#x1161;&#x11A8; is "precomposed" as a single code point, in the second one I
built it using combining jamos).

Basically, unless you have very specific requirements or are able to query the font, use an API that
segments strings into grapheme clusters wherever you need to deal with the notion of "character".


 [^1]: Emoji may not render as a single glyph depending on the font.
 [^2]: Part of the reason here is that I just find romanization confusing. There are some standardized ways to romanize which don't get used much. My friends and I romanize one way, different from the standardizations. My family members romanize things a completely different way and it's a bit hard to read. Then again, romanization _does_ hide the fact that my spelling in Hindi is atrocious :)
 [^3]: While writing this paragraph I discovered that wrapping text that contains lots of family emoji hangs Sublime. Neat.
 [^5]: It's possible to make work. You need a good terminal emulator, with the right settings, the right settings in your env vars, the right settings in irssi, and the right settings in screen. I think my current setup works well with non-ascii text but I'm not sure what I did to make it happen.
 [gloss-char]: http://unicode.org/glossary/#character
 [gloss-gc]: http://unicode.org/glossary/#grapheme_cluster

## Language defaults

Now, a lot of languages by default are now using Unicode-aware encodings. This is great. It gets rid
of the misconception that characters are one byte long.

But it doesn't get rid of the misconception that user-perceived characters are one code point long.

There are only two languages I know of which handle this well: Swift and Perl 6. I don't know much
about Perl 6's thing so I can't really comment on it, but I am really happy with what Swift does:

In Swift, the `Character` type is an extended grapheme cluster. This does mean that a
character itself is basically a string, since EGCs can be arbitrarily many code points long.

All the APIs by default deal with EGCs. The length of a string is the number of EGCs in it. They
are indexed by EGC. Iteration yields EGCs. The default comparison algorithm uses unicode
canonical equivalence, which I think is kind of neat. Of course, APIs that work with code
points are exposed too, you can iterate over the code points using `.unicodeScalars`.

The internal encoding itself is ... weird (and as far as I can tell not publicly exposed), but as a
higher level language I think it's fine to do things like that.

I strongly feel that languages should be moving in this direction, having defaults involving
grapheme clusters.

Rust, for example, gets a lot of things right -- it has UTF-8 strings. It internally uses byte
indices in slices. Explicit slicing usually uses byte indices too, and will panic if out of bounds.
The non-O(1) methods are all explicit, since you will use an iterator to perform the operation (E.g.
`.chars().nth(5)`). This encourages people to _think_ about the cost, and it also  encourages people
to coalesce the cost with nearby iterations -- if you are going to do multiple `O(n)` things, do
them in a single iteration! Rust `char`s represent code points. `.char_indices()` is
a useful string iteration method that bridges the gap between byte indexing and code points.

However, while the documentation does mention grapheme clusters, the stdlib is not aware of the
concept of grapheme clusters at all. The default "fundamental" unit of the string in Rust is
a code point, and the operations revolve around that. If you want grapheme clusters, you
may use [`unicode-segmentation`][crate-seg]

Now, Rust is a systems programming language and it just wouldn't do to have expensive grapheme
segmentation operations all over your string defaults. I'm very happy that the expensive `O(n)`
operations are all only possible with explicit acknowledgement of the cost. So I do think that going
the Swift route would be counterproductive for Rust. Not that it _can_ anyway, due to backwards
compatibility :)

But I would prefer if the grapheme segmentation methods were in the stdlib (they used to be).
This is probably not something that will happen, though I should probably push for the unicode
crates being move into the nursery at least.


 [crate-seg]: https://unicode-rs.github.io/unicode-segmentation/unicode_segmentation/trait.UnicodeSegmentation.html#tymethod.graphemes

 [UAX #29]: http://www.unicode.org/reports/tr29/#Grapheme_Cluster_Boundaries