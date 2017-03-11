---
layout: post
title: "Why quantum computing is weird"
date: 2017-03-11 14:25:18 -0800
comments: true
categories: 
---


_I've been meaning to write about physics for a while. When I started this blog the intention was to
write about a wide variety of interests, but I ended up focusing on programming, despite the fact
that I was doing more physics than programming for most of the lifetime of this blog. Time to change
that, and hopefully write about other non-programming topics too._

Quantum Computing. It's the new hip thing that's going to change the world[^1]. Someday.

In it's essence, where classical computing deals with "bits", which are on/off states, quantum
computing deals with "qubits", which are probabalistic quantum states that are often a mixture of on
and off. These have interesting properties which make certain kinds of so-far-hard computation very
easy to perform.

The goal of this post is not to teach quantum computing, rather to garner interest. I come to praise
quantum computing, not bury it[^2]. As a result, this post doesn't require a background in physics.
Having worked with very simple logic circuits is probably enough, though you may not even need that.

I'm basically going to sketch out an example of a very simple quantum algorithm. One that's very
logic-defying. It's even logic-defying for many who have studied quantum mechanics; it certainly
was for me. When I learned this first I could understand *why* it worked but there was a lot of
dissonance between that and my intuitive conviction that it was _wrong_.


 [^1]: What isn't?
 [^2]: The abstruseness of physics lives after it; the coolness is oft interred with its bones.

## The algorithm

{% img center /images/post/deutsch/deutsch-jozsa.png 600 %}

This is a quantum circuit (specifically, the circuit for the [Deutsch-Jozsa algorithm][deutsch]).
It's used to find out the nature of a black-box function `f(x)`, which takes in one qubit and outputs
another[^3]. For now, you can try to interpret this circuit as if it were a regular logic circuit.
You'll soon see that this interpretation is wrong, but it's useful for the purposes of this explanation.

To run this algorithm, you first construct an "oracle" out of the black-box function. The oracle,
given inputs `x` and `y`, has outputs `x` and `y ⊕ f(x)` (where `⊕` is the symbol for XOR, the
"exclusive OR").

As with logic circuits, data flow here goes from left to right. This circuit has two constant
inputs, a zero and a one. This is similar to how we might have constant "true" and "false" inputs
to logic circuits.

They are then passed through "Hadamard gates". These are _like_ NOT gates, in that applying them
twice is a no-op (they are their own inverse), but they're not actually NOT gates. I like to
describe them as "sideways NOT gates" since that description somewhat intuitively captures what's
going on with the qubits. What's important to note here is that they have one input and one
output, so they're unaffected by the goings-on in a different wire.

Once these inputs have been Hadamard'ed, they are fed to the oracle we constructed. The top input
goes on to become the top output. It's also passed through `f(x)` and XORd with the bottom input to make
the bottom output.

The top output is then Hadamard'ed again, and finally we observe its value.

Here's where the magic comes in. By observing the top output, _we will know the nature of `f(x)`_[^4].

Wait, what? The top output doesn't appear to have any interaction with `f(x)` at all! How can that work?

In fact, we could try to rewrite this circuit such that the measured output definitely has no interaction with
`f(x)` whatever, assuming that the Hadamard gate isn't doing anything funky[^7] (it isn't):

{% img center /images/post/deutsch/deutsch-jozsa-wrong.png 600 %}

How in the world does this work?

 [deutsch]: https://en.wikipedia.org/wiki/Deutsch%E2%80%93Jozsa_algorithm
 [^3]: This actually can be generalized to a function with n input and n output qubits, and the circuit stays mostly the same, except the top "x" line becomes n lines all initialized to 0 and passing through n parallel H gates.
 [^4]: Specifically, if the observation is 1, the function is a constant, whereas if the observation is 0, the function is "balanced" (gives a different output for inputs 1 and 0)
 [^7]: For Hadamard is an honorable gate. So are they all, all honorable gates.

## Why it works

Sadly, I can't give a satisfying explanation to _exactly_ why this works. This requires some quantum mechanics
background[^5] to grasp.

However, I can give a hopefully-satisfying explanation as to why our regular intuition doesn't work here.

First and foremost: The rewritten circuit I showed above? It's wrong. If this was a logic circuit, we could always do that,
but in quantum computing, T-junctions like the following can't exist:

{% img center /images/post/deutsch/deutsch-jozsa-tjunction.png 600 %}

This is due to the ["No Cloning theorem"][clone]. Unlike regular logic circuits, you can't
just "duplicate" a qubit. In some cases (like this one), you can try to create a similar qubit
via the same process (e.g. here we could take another 0 and pass it through a Hadamard gate), but
it's not the "same" qubit. Unlike bits, qubits have a stronger notion of unique identity.

And it's this sense of identity that fuels this algorithm (and most of quantum computing).

You see, while the top output of the oracle was `x`, it wasn't exactly the _same_ `x`. This `x` had
been mixed with the lower output. This means that the upper and lower outputs are now _entangled_,
with their state depending on each other. In fact, it's really misleading to show the output as two
wires in the first place -- it's really a single "entangled" state of two qubits that can't be
decomposed as a "top half" and a "bottom half". Of course, this way of representing quantum circuits
is still used because it's a tidy way of visualizing these circuits, and physicists are aware of the
caveats involved.

So what happens is that when you observe the top output, you are really doing a partial observation
on the combined state of the two outputs, and this includes some information about `f(x)`, which
leaks out when you perform the observation.

These properties of qubits make quantum circuits work significantly differently from regular logic
ones. On one hand, this severely restricts what you can do with them, but at the same time, new
avenues of erstwhile-impossible operations open up. Most useful quantum algorithms (like Shor's
factorization algorithm) involve a mixture of a classical algorithm and a quantum circuit due to
this reason. It's pretty cool!


 [^5]: If you do have this background, it's relatively straightforward; the Wikipedia page has the equations for it.
 [clone]: https://en.wikipedia.org/wiki/No-cloning_theorem

