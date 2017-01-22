---
layout: post
title: "Breaking our Latin-1 assumptions"
date: 2017-01-15 13:34:16 -0800
comments: true
categories: 
---

So in my [previous post][post-prev] I explored a specific (wrong) assumption that programmers
tend to make about the nature of code points and text.

I was asked multiple times about other assumptions we tend to make. There are a lot. Most
Latin-based scripts are simple, but most programmers spend their time dealing with Latin
text so these complexities never come up.

I thought it would be useful to share my personal list of
[scripts that break our Latin-1 assumptions][tweet]. This is a list I mentally check against
whenever I am attempting to reason about text. I check if I'm making any assumptions that
break in these scripts. *Most* of these concepts are independent of Unicode; so any program
would have to deal with this regardless of encoding.

I again recommend going through [eevee's post][vee], since it covers many related issues.
[Awesome-Unicode] also has a lot of random tidbits about Unicode.

Anyway, here's the list. Note that a lot of the concepts here exist in scripts other than the
ones listed, these are just the scripts _I_ use for comparing.


 [post-prev]: http://manishearth.github.io/blog/2017/01/14/stop-ascribing-meaning-to-unicode-code-points
 [tweet]: https://twitter.com/ManishEarth/status/810582690906931200
 [vee]: https://eev.ee/blog/2015/09/12/dark-corners-of-unicode/
 [Awesome-Unicode]: https://github.com/jagracey/Awesome-Unicode

## Arabic / Hebrew

Both Arabic and Hebrew are RTL scripts; they read right-to-left. This may even affect how
a page is laid out, see the [Hebrew Wikipedia][he-wiki].

They both have a concept of letters changing how they look depending on where they are in the word.
Hebrew has the "sofit" letters, which use separate code points. For example, Kaf (כ) should be typed
as ך at the end of a word. Greek has something similar with the sigma.

In Arabic, the letters can have up to four different forms, depending on whether they start a word,
end a word, are inside a word, or are used by themselves. These forms can look very different. They
don't use separate code points for this; however. You can see a list of these forms [here][ar-forms]

As I mentioned in the last post, U+FDFD (﷽), a ligature representing the Basamala,
is also a character that breaks a lot of assumptions.


 [he-wiki]: https://he.wikipedia.org/wiki/%D7%A2%D7%9E%D7%95%D7%93_%D7%A8%D7%90%D7%A9%D7%99
 [ar-forms]: https://en.wikipedia.org/wiki/Arabic_alphabet#Table_of_basic_letters

## Indic scripts

Indic scripts are _abugidas_, where you have consonants with vowel modifiers. For example, क is
"kə", where the upside down "e" is a schwa, something like an "uh" vowel sound. You can change the
vowel by adding a diacritic (e.g `ा`); getting things like का ("kaa") को ("koh") कू ("koo").

You can also mash together consonants to create consonant clusters. The "virama" is a vowel-killer
symbol that removes the inherent schwa vowel. So, `क` + `्` becomes `क्`. This sound itself is
unpronounceable since क is a stop consonant (vowel-killed consonants can be pronounced for nasal and some other
consonants though), but you can combine it with another consonant, as `क्` + `र` ("rə"), to get `क्र`
("krə"). Consonants can be strung up infinitely, and you can stick one or more vowel diacritics
after that. Usually, you won't see more than two consonants in a cluster, but larger ones are not
uncommon in Sanskrit (or when writing down some onomatopoeia). They may not get rendered as single
glyphs, depending on the font.

One thing that crops up is that there's no unambiguous concept of a letter here. There
is a concept of an "akshara", which basically includes the vowel diacritics, and
depending on who you talk to may also include consonant clusters. Often things are
clusters an akshara depending on whether they're drawn with an explicit virama
or form a single glyph.

In general the nature of the virama as a two-way combining character in Unicode is pretty new.

## Hangul

Korean does its own fun thing when it comes to conjoining characters. Hangul has a concept
of a "syllable block", which is basically a letter. It's made up of a leading consonant,
medial vowel, and an optional tail consonant. &#x1100;&#x1161;&#x11A8; is an example of
such a syllable block, and it can be typed as &#x1100; + &#x1161; + &#x11A8;. It can
also be typed as &#xAC01;, which is a "precomposed form" (and a single code point).

These characters are examples of combining characters with very specific combining rules. Unlike
accents or other diacritics, these combining characters will combine with the surrounding characters
only when the surrounding characters form an L-V-T or L-V syllable block.

As I mentioned in my previous post, apparently syllable blocks with more (adjacent) Ls, Vs, and Ts are
also valid and used in Old Korean, so the grapheme segmentation algorithm in Unicode considers
"ᄀᄀᄀ&#x1100;&#x1161;&#x11A8;ᆨᆨ" to be a single grapheme ([it explicitly mentions this][old-jamo]).
I'm not aware of any fonts which render these as a single syllable block, or if that's even
a valid thing to do.


 [old-jamo]: http://www.unicode.org/reports/tr29/#Hangul_Syllable_Boundary_Determination
## Han scripts

So Chinese (Hanzi), Japanese (Kanji[^1]), Korean (Hanja[^2]), and Vietnamese (Hán tự, along with Chữ
Nôm [^3]) all share glyphs, collectively called "Han characters" (or CJK characters[^7]). These
languages at some point in their history borrowed the Chinese writing system, and made their own
changes to it to tailor to their needs.

Now, the Han characters are ideographs. This is not a phonetic script; individual characters
represent words. The word/idea they represent is not always consistent across languages. The
pronounciation is usually different too. Sometimes, the glyph is drawn slightly differently based on
the language used. There are around 80,000 Han ideographs in Unicode right now.

The concept of ideographs itself breaks some of our Latin-1 assumptions. For example, how
do you define Levenshtein edit distance for text using Han ideographs? The straight answer is that
you can't, though if you step back and decide *why* you need edit distance you might be able
to find a workaround. For example, if you need it to detect typos, the user's input method
may help. If it's based on pinyin or bopomofo, you might be able to reverse-convert to the
phonetic script, apply edit distance in that space, and convert back. Or not. I only maintain
an idle curiosity in these scripts and don't actually use them, so I'm not sure how well this would
work.

The concept of halfwidth character is a quirk that breaks some assumptions.

In the space of Unicode in particular, all of these scripts are represented by a single set of
ideographs. This is known as "Han unification". This is a pretty controversial issue, but the
end result is that rendering may sometimes be dependent on the language of the text, which
e.g. in HTML you set with a `<span lang=whatever>`. [The wiki page][enc-dep] has some examples of
encoding-dependent characters.

Unicode also has a concept of variation selector, which is a code point that can be used to
select between variations for a code point that has multiple ways of being drawn. These
do get used in Han scripts.

While this doesn't affect rendering, Unicode, as a system for _describing_ text,
also has a concept of interlinear annotation characters. These are used to represent
[furigana / ruby][ruby]. Fonts don't render this, but it's useful if you want to represent
text that uses ruby. Similarly, there are [ideographic description sequences][ids] which
can be used to "build up" glyphs from smaller ones when the glyph can't be encoded in
Unicode. These, too, are not to be rendered, but can be used when you want to describe
the existence of a character like [biáng][biang]. These are not things a programmer
needs to worry about; I just find them interesting and couldn't resist mentioning them :)

Japanese speakers haven't completely moved to Unicode; there are a lot of things out there
using Shift-JIS, and IIRC there are valid reasons for that (perhaps Han unification?). This
is another thing you may have to consider.

Finally, these scripts are often written _vertically_, top-down. [Mongolian], while
not being a Han script, is written vertically sideways, which is pretty unique. The
CSS [writing modes][wm] spec introduces various concepts related to this, though that's mostly in the
context of the Web.


 [^1]: Supplemented (but not replaced) by the Hiragana and Katakana phonetic scripts. In widespread use.
 [^2]: Replaced by Hangul in modern usage
 [^3]: Replaced by chữ quốc ngữ in modern usage, which is based on the Latin alphabet
 [^7]: "CJK" (Chinese-Japanese-Korean) is probably more accurate here, though it probably should include "V" for Vietnamese too. Not all of these ideographs come from Han; the other scripts invented some of their own. See: Kokuji, Gukja, Chữ Nôm.
 [enc-dep]: https://en.wikipedia.org/wiki/Han_unification#Examples_of_language-dependent_glyphs
 [Mongolian]: https://en.wikipedia.org/wiki/Mongolian_script
 [ruby]: https://en.wikipedia.org/wiki/Ruby_character
 [ids]: https://en.wikipedia.org/wiki/Chinese_character_description_languages#Ideographic_Description_Sequences
 [biang]: https://en.wikipedia.org/wiki/Biangbiang_noodles#Chinese_character_for_bi.C3.A1ng
 [wm]: https://drafts.csswg.org/css-writing-modes/

## Thai / Khmer / Burmese / Lao

These scripts don't use spaces to split words. Instead, they have rules for what kinds of sequences
of characters start and end a word. This can be determined programmatically, however IIRC the
Unicode spec does not attempt to deal with this. There are libraries you can use here instead.

## Latin scripts themselves!

Turkish is a latin-based script. But it has a quirk: The uppercase of "i" is
a dotted "İ", and the lowercase of "I" is "ı". If doing case-based operations, try to use
a Unicode-aware library, and try to provide the locale if possible.

Also, not all code points have a single-codepoint uppercase version. The eszett (ß) capitalizes
to "SS". There's also the "capital" eszett ẞ, but its usage seems to vary and I'm not exactly
sure how it interacts here.

While Latin-1 uses precomposed characters, Unicode also introduces ways to specify the same
characters via combining diacritics. Treating these the same involves using the normalization
algorithms (NFC/NFD).

## Emoji

Well, not a script[^4]. But emoji is weird enough that it breaks many of our assumptions. The
scripts above cover most of these, but it's sometimes easier to think of them
in the context of emoji.

The main thing with emoji is that you can use a zero-width-joiner character to glue emoji together.

For example, the family emoji 👩‍👩‍👧‍👦 (may not render for you) is made by using the woman/man/girl/boy
emoji and gluing them together with ZWJs. You can see its decomposition in [uniview].

There are more sequences like this, which you can see in the [emoji-zwj-sequences] file. For
example, MAN + ZWJ + COOK will give a male cook emoji (font support is sketchy).
Similarly, SWIMMER + ZWJ + FEMALE SIGN is a female swimmer. You have both sequences of
the form "gendered person + zwj + thing", and "emoji containing human + zwj + gender",
IIRC due to legacy issues[^5]

There are also [modifier characters][fitz] that let you change the skin tone of an emoji that
contains a human (or human body part, like the hand-gesture emojis) in it.

Finally, the flag emoji are pretty special snowflakes. For example, 🇪🇸 is the Spanish
flag. It's made up of [two regional indicator characters for "E" and "S"][ri-view].

Unicode didn't want to deal with adding new flags each time a new country or territory pops up. Nor
did they want to get into the tricky business of determining what a country _is_, for example
when dealing with disputed territories. So instead, they just defined these regional indicator
symbols. Fonts are supposed to take pairs of RI symbols[^6] and map the country code to a flag.
This mapping is up to them, so it's totally valid for a font to render a regional indicator
pair "E" + "S" as something other than the flag of Spain. On some Chinese systems, for example,
the flag for Taiwan (🇹🇼) may not render.


 [^4]: Back in _my_ day we painstakingly typed actual real words on numeric phone keypads, while trudging to 🏫 in three feet of ❄️️, and it was uphill both ways, and we weren't even _allowed_ 📱s in 🏫. Get off my lawn!
 [^5]: We previously had individual code points for professions and stuff and they decided to switch over to using existing object emoji with combiners instead of inventing new profession emoji all the time
 [^6]: 676 countries should be enough for anybody
 [uniview]: https://r12a.github.io/uniview/?charlist=%F0%9F%91%A9%E2%80%8D%F0%9F%91%A9%E2%80%8D%F0%9F%91%A7%E2%80%8D%F0%9F%91%A6
 [emoji-zwj-sequences]: http://unicode.org/Public/emoji/4.0/emoji-zwj-sequences.txt
 [fitz]: http://www.unicode.org/reports/tr51/#Diversity
 [ri-view]: https://r12a.github.io/uniview/?charlist=%F0%9F%87%AA%F0%9F%87%B8


--------------

I hightly recommend comparing against this relatively small list of scripts the next time you
are writing code that does heavy manipulation of user-provided strings.


