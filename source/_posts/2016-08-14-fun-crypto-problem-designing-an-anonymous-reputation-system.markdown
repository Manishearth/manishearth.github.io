---
layout: post
title: "Fun crypto problem: Designing an anonymous reputation system"
date: 2016-08-14 12:15:31 -0800
comments: true
categories: cryptography
---

One of the reasons I like crypto is that it's a gold mine of interesting problems which feel
like they are impossible to solve and if a solution exists, it must be magic.

The other day, I came across one such problem [here][sarah-tweet], by @SarahJamieLewis

> Is there a scheme where A can give reputation points to B, & later, B presenting as C can prove
> their reputation (without revealing A or B)?

(I recommend trying to solve this yourself before reading ahead)

The problem isn't completely defined because we don't know how "reputation" is supposed to work. A
simple model is to think of it as currency, and use Bitcoin as a proxy. Of course, a real reputation
system probably would be different from currency. There might only be a small set of authorized
reputation "sellers" (this can still be built on top of Bitcoin, or you can use a system similar to
the CA system for TLS certificates). Or there might be a system in which each person can vote for
another person at most once (though this needs to be designed in a way that is resilient to sybil
attacks).

Let us assume that there is a ledger out there, where each ledger entry is a certificate saying that
entity X has given one reputation point to entity Y. A public key is included, where the private key
is only known to Y. This model cleanly applies to both Bitcoin and CA systems -- in Bitcoin, the
transaction is the "certificate", and in the CA system the certificate is the certificate.

For additional anonymity, you can have a different private key for each certificate. I'm going to
assume this is the case, though the solutions don't change much if it isn't.

## Solution via ZKP

I'm very fond of the concept of a zero-knowledge proof, and when you have a hammer everything looks
like a nail.

So my first solution was one involving zero-knowledge proofs.

Construct the problem "Given the certificates in this ledger and X private keys, prove that these
private keys each have one certificate they correspond to, and that the keys are distinct".

In this problem, the certificates (public keys) are hardcoded, whereas the private keys are inputs.
This sort of algorithm can be written as a sequential logic circuit, assuming that the method of
signing can be. We can then perform a zero-knowledge proof of this problem using the ZKP for general
execution [outlined here][zkp-general]. The prover inserts their private keys into the algorithm,
run the algorithm, and prove that the execution was faithful and had an output of true using the ZKP.

Since the ZKP doesn't leak any information about its inputs, it doesn't leak which certificates
were the ones for which the prover had private keys, so it doesn't leak the identities of A or B.

However, this is overkill. The general ZKP gets very expensive as the size of the algorithm, and
since the ledger was hardcoded in it, this ZKP will probably take a while (or a lot of computational
power) to execute. One can perform it with a subset of the ledger picked by the prover, but
repeating the process may slowly reveal the identity of the prover via the intersection of these
subsets.

## Solution via secret-sharing

(This solution is technically a ZKP too, but it doesn't use the "general" ZKP algorithm which
while expensive can be used for any combinatorical verification algorithm)

Once I'd gotten the "use a ZKP!" solution out of my system, I thought about it more and realized
that the problem is very close to a secret-sharing one.

Secret-sharing is when you want to have a cryptographic "lock" (a shared secret) which can only be
revealed/opened when the requisite quorum of (any) X keys out of N total keys is used.

Shamir's secret sharing is a nice algorithm using polynomials that lets you do this.

In this situation, we want to prove that we have X private keys out of N total certificates in the
ledger.

The verifier (Victor) can construct a secret sharing problem with a single secret and N secret-
sharing-keys (in the case of Shamir, these would be N x,y-coordinate pairs). Each such key is paired
with a certificate, and is encrypted with the corresponding public key of that certificate.

The prover (Peggy) is given all of these encrypted secret-sharing keys, as well as the certificates
they correspond to.

If Peggy legitimately has X reputation, she has the X private keys necessary to obtain X of the
secret sharing keys by decrypting them. From this, she can obtain the secret. By showing the secret
to Victor, she has proven that she has at least X private keys corresponding to certificates in the
ledger, and thus has at least X reputation. In the process, _which_ certificates were involved is
not revealed (so both the reputation-giver and reputation-receiver) stay anonymous.

Or was it?

Victor can construct a malicious secret sharing problem. Such a problem would basically reveal a
different secret depending on the secret-sharing-keys Peggy uses. For example, in Shamir's secret
sharing, Victor can just give N random coordinates. X of those coordinates will always create a
degree-X curve, but the curves obtained from different sets of X coordinates will probably have a
different constant term (and thus a different secret).

The secret-sharing problem needs to be transmitted in a way that makes it possible for Peggy to
verify that it's not malicious.

One way to do it is to make it possible to uncover _all_ the secret-sharing-keys, but _only_ after
the secret has been found. In Shamir's algorithm, this can be done by pre-revealing the x
coordinates and only encrypting the y coordinates. Once Peggy has found the secret, she has the
entire polynomial curve, and can input the remaining x coordinates into the curve to find the
remaining secret sharing keys (and then verify that they have been encrypted properly).

This is _almost perfect_. User "otus" on Crypto Stack Exchange [pointed out my mistake][cryptose].

The problem with this scheme (and the previous one to a lesser degree) is that Peggy could simply
brute-force the values of the y coordinates beforehand.

This can be solved by using nonces. Instead of encrypting each y-coordinate, Victor encrypts each
y-coordinate, _plus a nonce_. So, instead of encrypting the y-coordinate "42", a string like
"da72ke8lv0q-42" will be encrypted.

On decryption, it is easy to extract the coordinate from the plaintext (presumably the scheme used
to add the nonce would be decided upon beforehand). However, we can't brute-force for the plaintext
anymore, because the ciphertext isn't the encryption of a low-entropy value like a regular, smallish
number, it's the encryption of a relatively high-entropy value.

So far, this prevents brute forcing, but it also prevents Peggy from verifying that the secret-
sharing problem was non-malicious, since she doesn't know the nonces. Nor can these be pre-shared
with her, since she can just use them to brute force again.

The solution here is for Victor to use the shared secret as a symmetric key, encrypt all of the
nonces with it, and share them with Peggy. Until Peggy knows this key, she cannot use the nonces to
brute force. Once she knows this key, she can decrypt the values for the nonces and use them to
verify that the nonces are correct.

This is exactly the property we need. If Peggy doesn't have enough private keys (reputation points),
she won't have the secret and can't prove her reputation to Victor. Once Peggy does have the quorum
of keys, she will know the symmetric key, be able to decrypt the nonces, and use these nonces to
verify that the other N-X ciphertexts fall on the curve which she has obtained. Once she has
verified this, she can present the shared secret/symmetric key to Victor, who will know that she
had enough keys to crack the secret sharing problem and thus has at least X reputation.

----------------

This was quite an entertaining problem to solve (and it got me thinking about ZKPs again, which
made me write my [previous post][post-prev]). Thanks, Sarah!

Got an alternate solution (or other similar fun problems)? Let me know!


 [sarah-tweet]: https://twitter.com/SarahJamieLewis/status/763060674956173314
 [zkp-general]: http://manishearth.github.io/blog/2016/03/05/exploring-zero-knowledge-proofs/
 [cryptose]: http://crypto.stackexchange.com/q/39274/2081
 [post-prev]: http://manishearth.github.io/blog/2016/08/10/interactive-sudoku-zero-knowledge-proof/