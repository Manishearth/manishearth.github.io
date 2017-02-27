---
layout: post
title: "Clarifying misconceptions about SHAttered"
date: 2017-02-26 00:30:56 -0800
comments: true
categories: 
---


This week Google published a [SHA-1 collision][shattered].

There's a lot of confusion about the implications of this. A lot of this is due to differences of
opinion on what exactly constitutes a "new" collision. I [tweeted about this][twit]. The webpage
for the attack itself is misleading, saying that the answer to "Who is capable of mounting this attack?"
is people with Google-esque resources. This depends on what exactly you mean by "this attack".

So I'm seeing a lot of "oh well just another anti-milestone for SHA, doesn't affect anyone since its
still quite expensive to exploit" reactions, as well as the opposite "aaaaa everything is on fire"
reaction. Both are wrong. It has practical implications for you even if you are certain that you
won't attract the ire of an entity with a lot of computational power. None of these implications,
however, are likely to be disastrous.

TLDR: Now *anyone*, without needing Google-esque resources,
can generate two colliding PDFs with arbitrary visual content in each.


(In fact, there's already [a PDF collision-generator][supercollider] up where
you can upload two images and get a PDF with collisions in it)

 [shattered]: https://shattered.io/
 [twit]: https://twitter.com/ManishEarth/status/835557328308969472
 [supercollider]: http://alf.nu/SHA1

## Okay, back up a bit. What's a hash? What's SHA-1?

I explained this a bit in my older post about [zero-knowledge-proofs][zkp].

In essence, a hash function takes some data (usually of arbitrary size), and produces a value called
a _hash_ (usually of fixed size). The function has some additional properties:

 - In almost all cases, a small perturbation in the input will lead to a large perturbation in the hash
 - Given an input and its hash, it is computationally hard to find an alternate input producing the same hash
 - It's also hard to just find two inputs that has to the same value, though this is usually easier than the previous one
 
when two inputs hash to the same value, this is called a collision. As mentioned, is easier to find
_a_ collision, over finding a colliding alternate input for a known input.

SHA-1 is one such hash function. It's been known for a while that it's insecure, and the industry has
largely moved off of it, but it's still used,


 [zkp]: http://manishearth.github.io/blog/2016/03/05/exploring-zero-knowledge-proofs/

## What did the researchers do?

They found a hash collision for SHA-1. In essence, they found two strings, `A` and `B`, where
`SHA1(A) == SHA1(B)`.

_However_, given the way SHA-1 works, this means that you can generate infinitely many other
such pairs of strings. And given the nature of the exact `A` and `B` they created, it is possible
to use this to create arbitrary colliding PDFs.

Basically, SHA-1 (and many other hash functions), operate on "blocks". These are fixed-size chunks
of data, where the size is a property of the hash function. For SHA1 this is 512 bits.

The function starts off with an "initial" built-in hash. It takes the first block of your data and
this hash, and does some computation with the two to produce a new hash, which is its state after
the first block.

It will then take this hash and the second block, and run the same computations to produce
a newer hash, which is its state after the second block. This is repeated till all blocks have
been processed, and the final state is the result of the function.

There's an important thing to notice here. At each block, the only inputs are the block itself and the
hash of the string up to that block.

This means, if `A` and `B` are of a size that is a multiple of the block size, and `SHA1(A) == SHA1(B)`,
then `SHA1(A + C) == SHA1(B + C)`. This is because, when the hash function reaches `C`, the state will
be the same due to the hash collision, and after this point the next input blocks are identical in
both cases, so the final hash will be the same.

Now, while you might consider `A+C, B+C` to be the "same collision" as `A, B`, the implications
of this are different than just "there is now one known pair of inputs that collide", since everyone
now has the ability to generate new colliding inputs by appending an arbitrary string to `A` and `B`.

Of course, these new collisions have the restriction that the strings will always start with `A` or
`B` and the suffixes will be identical. If you want to break this restriction, you will
have to devote expensive resources to finding a new collision, like Google did.

## How does this let us generate arbitrary colliding PDFs?

So this exploit actually uses features of the JPEG format to work. It was done in
a PDF format since JPEGs often get compressed when sent around the Internet. However,
since both A and B start a partial PDF document, they can only be used to generate colliding
PDFs, not JPEGs.

I'm going to first sketch out a simplified example of what this is doing, using a hypothetical
pseudocode-y file format. The researchers found a collision between the strings:

- A: `<header data> COMMENT(<nonce for A>) DISPLAY IMAGE 1`
- B: `<header data> COMMENT(<nonce for B>) DISPLAY IMAGE 2`

Here, `<header data>` is whatever is necessary to make the format work, and the "nonce"s are
strings that make `A` and `B` have the same hash. Finding these nonces is where
the computational power is required, since you basically have to brute-force a solution.

Now, to both these strings, they append a suffix C: `IMAGE 1(<data for image 1>) IMAGE 2(<data for image 2>)`.
This creates two complete documents. Both of the documents contain both images, but each one is instructed
to display a different one. Note that since `SHA1(A) == SHA1(B)`, `SHA1(A + C) = SHA1(B + C)`, so these
final documents have the same hash.

The contents of `C` don't affect the collision at all. So, we can insert any two images in `C`, to create
our own personal pair of colliding PDFs.

The actual technique used is similar to this, and it relies on JPEG comment fields. They have found
a collision between two strings that look like:

```text
pdf header data                       | String A
begin embedded image                  |  
    jpg header data                   |
    declare jpg comment of length N   |
    random nonce of length N          | (comment ends here) 
                                     ---
    image 1, length L                 | String C
    jpg EOF byte (2 bytes)            |
    image 2                           |
end embedded image                    |

and

pdf header data                       | String B
begin embedded image                  |
    jpg header data                   |
    declare jpg comment of length M   |
    random nonce of length M-L-2      |
                                     ---
    image 1, length L                 | String C
    jpg EOF marker (2 bytes)          | (comment ends here)
    image 2                           |
end embedded image                    |
```

By playing with the nonces, they managed to generate a collision between `A` and `B`. In the first
pdf, the embedded image has a comment containing only the nonce. Once the JPEG reader gets past that
comment, it sees the first image, displays it, and then sees the end-of-file marker and decides to
stop. Since the PDF format doesn't try to interpret the image itself, the PDF format won't be
boggled by the fact that there's some extra garbage data after the JPEG EOF marker. It
simply takes all the data between the "begin embedded image" and "end embedded image" blocks,
and passes it to the JPEG decoder. The JPEG decoder itself stops after it sees the end of file
marker, and doesn't get to the extra data for the second image.

In the second pdf, the jpg comment is longer, and subsumes the first image (as well as the EOF marker)
Thus, the JPEG decoder directly gets to the second image, which it displays.

Since the actual images are not part of the original collision (A and B), you can substitute any pair
of jpeg images there, with some length restrictions.

## What are the implications?

This does mean that you should not trust the integrity of a PDF when all you have
to go on is its SHA-1 hash. Use a better hash. _Anyone can generate these colliding PDFs
now._

Fortunately, since all such PDFs will have the same prefix A or B, you can detect when
such a deception is being carried out.

Don't check colliding PDFs into SVN. [Things break][webkit].

In some cases it is possible to use the PDF collision in other formats. For example,
[it can be used to create colliding HTML documents][html]. I think it can be used to colide
ZIP files too.

Outside the world of complex file formats, little has changed. It's still a bad idea to use SHA-1.
It's still possible for people to generate entirely new collisions like Google did, though this
needs a lot of resources. It's possible that someone with resources has already generated such a
"universal-key collision" for some other file format[^1] and will use it on you, but this was
equally possible before Google published their attack.

This does not make it easier to collide with arbitrary hashes -- if someone else
has uploaded a document with a hash, and you trust them to not be playing any tricks,
an attacker won't be able to generate a colliding document for this without immense
resources. The attack only works when the attacker has control over the initial document;
e.g. in a bait-and-switch-like attack where the attacker uploads document A, you read and verify it
and broadcast your trust in document A with hash `SHA(A)`, and then the attacker switches it with
document B.

 [webkit]: https://bugs.webkit.org/show_bug.cgi?id=168774#c27
 [html]: https://mobile.twitter.com/arw/status/834883944898125824
 [^1]: Google's specific collision was designed to be a "universal key", since A and B are designed to have the image-switching mechanism built into it. Some other collision may not be like this; it could just be a collision of two images (or whatever) with no such switching mechanism. It takes about the same effort to do either of these, however, so if you have a file format that can be exploited to create a switching mechanism, it would always make more sense to build one into any collision you look for.