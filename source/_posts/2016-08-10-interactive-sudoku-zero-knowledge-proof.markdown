---
layout: post
title: "Interactive Sudoku zero-knowledge proof"
date: 2016-08-10 11:21:19 -0800
comments: true
categories: 
---

Back in March I was particularly interested in Zero-Knowledge Proofs. At the time, I wrote
[a long blog post][zkp-post] introducing them and explaining how the ZKP for generic execution
works.

I was really enjoying learning about them, so I decided to do a presentation on them in my crypto
course. Sadly there wasn't going to be time for explaining the structure of the proof for general
execution, but I could present something more fun: Sudoku.

Sudoku solutions can be proven via ZKP. That is to say, if Peggy has a solution to Victor's Sudoku
problem, she can prove that she has a valid solution without ever revealing any information about
her solution to Victor (aside from the fact that it is valid).

To make the ZKP easier to explain, I wrote an [interactive version of it][interactive].

I planned to write about it then, but completely forgot till now. Oops.

I'm first going to explain how the ZKP is carried out before I explain how the interactive verifier
works. If you aren't familiar with ZKPs, you might want to read
[my previous post on the subject][zkp-post] up to and including the part about proving graph colorings.

## Proving Sudoku

This proof is going to be carried out very similarly to the graph coloring proof. Indeed, Sudoku can
be reduced to a graph coloring problem, though that's not how we're going to obtain the ZKP.

Victor has a Sudoku problem:

{% img /images//sudoku-zkp/sudoku-problem.png 300 %}

Peggy has a solution:

{% img /images//sudoku-zkp/sudoku-solution.png 300 %}

In order to not leak information about her solution, Peggy permutes it:

{% img /images//sudoku-zkp/sudoku-solution-permuted.png 300 %}

Basically, there is a 1-1 mapping between the old digits and the new ones. In this specific
permutation, all 3s are replaced by 4s, all 1s by 5s, etc.

She now commits to this permutation by committing to every individual cell. A random nonce is
obtained for each cell, and the contents of that cell are hashed along with the nonce. This
is the same commitment procedure used in the graph coloring ZKP.

These commitments are now sent over to Victor.

Victor ponders for a bit, and demands that Peggy reveal the third row of the sudoku square.

{% img /images//sudoku-zkp/victor-ask.png 300 %}

(Note that this is the non-permuted problem statement)

This row is marked in orange. There are some additional elements marked in green, which I shall
get to shortly.

Peggy reveals the permuted values for this row:

{% img /images//sudoku-zkp/peggy-reveal-orange.png 300 %}

Victor can now verify that all digits 1-9 appear within this permuted row, and that they match the
commitments. This means that they appear in the original solution too (since permutation doesn't
change this fact), and, at least for this row, the solution is correct. If Peggy didn't have a
solution, there was a chance she'd be caught in this round if Victor had asked for the right
set of 9 squares to be revealed.

The procedure can be repeated (with a new permutation each time) to minimize this chance, with
Victor asking to reveal a row, column, or 3x3 subsquare each time, until he is certain that Peggy
has a solution.

But wait! This only works towards proving that Peggy has a valid Sudoku solution, not that this
is _the_ solution to Victor's specific problem. Victor only verified that each row/column/subsquare
had no duplicates, a property which is true for all sudoku solutions!

This is where the green squares come in. For any given set of "orange squares" (a row, column, or
3x3 subsquare), we take the "preset" digits appearing in the problem statement (In this case: 7, 8,
and 6) in that set of squares. All other instances of those digits preset in the problem statement
form the set of "green squares":

{% img /images//sudoku-zkp/victor-ask.png 300 %}

Peggy reveals the permuted values for both the green and orange squares each time:

{% img /images//sudoku-zkp/peggy-reveal-both.png 300 %}

In addition to verifying that there are no duplicates in the orange squares, Victor additionally
verifies that the permutation is consistent. For example, the 7th element in that row is a 6, which
is already preset in the problem statement. There are two other 6s in the problem statement, one in
the 5th row 8th column, and one in the 7th row 1st column. If the permutation is consistent, their
corresponding squares in the revealed portion of the permuted solution should all have the same
digit. In this case, that number is 1. Similarly, the 5th element in that row is a preset 8, and
there's a corresponding green square in the 5th row last column that also has an 8. In the permuted
solution, Victor verifies that they both have the same digit, in this case 7.

This lets Victor ensure that Peggy has a solution to his sudoku problem. The fact that two given
squares must share the same digit is invariant under permutations, so this can be safely verified.
In fact, a sudoku problem is really just a problem saying "Fill these 81 squares with 9 symbols such
that there are no duplicates in any row/column/subsquare, and these three squares have the same
symbol in them, and these five squares have the same symbol in them, and ...". So that's all we
verify: There should be no duplicates, and the digits in certain sets of squares should be the same.

Note that revealing the green squares doesn't reveal additional information about Peggy's solution.
Assuming Peggy's solution is correct, from comparing the problem statement with the
revealed/permuted values, Victor already _knows_ that in the permutation, 7 has become 6, 8 has
become 7, and 6 has become 1. So he already knows what the other preset green squares contain, he
is just verifying them.

We cannot reveal anything _more_ than the green squares, since that would reveal additional
information about the permutation and thus the solution.

Edit: This actually _still_ isn't enough, which was pointed out to me by "dooglius"
[here][peggy-cheat]. Basically, if the sudoku problem has two digits which only appear once each,
there is nothing that can stop Peggy from coming up with a solution where these two digits have been
changed to something else (since they'll never be in a green square). Fixing this is easy, we allow
Victor to ask Peggy to reveal just the permuted values of the presets (without simultaneously
revealing a row/column/subsquare). Victor can then verify that the preset-permutation mapping is
consistent (all presets of the same value map to the same permutation) and 1-1.

This check actually obviates the need of the green squares entirely. As long as there is a chance
that Victor will ask for the presets to be revealed instead of a row/column/subsquare, Peggy cannot
try to trick Victor with the solution of a different sudoku problem without the risk of getting
caught when Victor asks for the presets to be revealed. However, the green squares leak no
information, so there's no problem in keeping them as a part of the ZKP as a way to reduce the
chances of Peggy duping Victor.

 [peggy-cheat]: https://github.com/Manishearth/sudoku-zkp/issues/1

## The interactive verifier

Visit the [interactive verifier][interactive]. There's a sudoku square at the top which you can fill
with a problem, and you can fill the solution in on the first square on the Prover side -- fill this
in and click Start. Since I know nobody's going to actually do that, there's a "Fill with known
problem/solution" that does this for you.

Once you've initiated the process, the ball is in the Prover's court. The Prover must first permute
the solution by clicking the Permute button. You can edit the permutation if you like (to introduce
a flaw), or manually do this after clicking the button.

Once you've clicked the button, generate nonces by clicking the next one, "Populate Nonces". These,
too can be edited. You can generate hashes (which can also be edited) by clicking the next button,
and after that send the hashes (commitments) over to the Verifier's side.

The ball is now in the Verifier's court. As you can see, there's a set of hashes on the Verifier's
side. The Verifier only knows the problem statement and whatever is visible on their side of the
screen, and nothing more.

You, acting on behalf of the Verifier, can now select a row/column/subsquare/preset using the
dropdown and text box on the Verifier. As you select, the orange/green squares that are going to be
revealed will be shown. When satisfied with your choice, click "Reveal", and the Prover will
populate your squares with the permuted values and nonces. "Verify" will verify that:

 - The appropriate elements and hashes are revealed
 - The hash is equal to `SHA256(nonce + "-" + digit)`
 - The orange squares contain distinct digits.
 - The green squares contain digits that match with the orange squares they correspond to from the problem solution


Once you click verify, it will show the probability of correctness (this isn't an exact value, it's
calculated using an approximate formula that doesn't depend on the problem statement), and the ball
moves back into Peggy's court, who can permute her solution again and continue. The probability
slowly increases each round.

Doing this manually till it reaches 99% is boring, so there's a button at the top ("Run
automatically") which can be clicked to run it for a given number of rounds, at any stage in the
process once started. If you tamper with one of the values in the permuted solution, and run it
for ~20 runs, it usually gets caught.

Have fun!


[zkp-post]: http://manishearth.github.io/blog/2016/03/05/exploring-zero-knowledge-proofs/
[interactive]: https://manishearth.github.io/sudoku-zkp/zkp.html