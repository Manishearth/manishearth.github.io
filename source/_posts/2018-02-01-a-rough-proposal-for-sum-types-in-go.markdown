---
layout: post
title: "A rough proposal for sum types in Go"
date: 2018-02-01 20:26:26 +0530
comments: true
categories: rust programming mozilla
---

Sum types are pretty cool. Just like how a struct is basically "This contains one of these _and_ one of these",
a sum type is "This contains one of these _or_ one of these".

So for example, the following sum type in Rust:

```rust
enum Foo {
    Stringy(String),
    Numerical(u32)
}
```

or Swift:

```swift
enum Foo {
    case stringy(String),
    case numerical(Int)
}
```

would be one where it's either `Foo::Stringy` (`Foo::stringy` for swift), containing a `String`,
_or_ `Foo::Numerical`, containing an integer.

This can be pretty useful. For example, messages between threads are often of a "this or that or that or that"
form.

The nice thing is, matching (switching) on these enums is usually _exhaustive_ -- you must list all
the cases (or include a default arm) for your code to compile. This leads to a useful component
of type safety -- if you add a message to your message passing system, you'll know where to update it.

Go doesn't have these. Go _does_ have interfaces, which are dynamically dispatched. The drawback here
is that you do not get the exhaustiveness condition, and consumers of your library can even add further
cases. (And, of course, dynamic dispatch can be slow). You _can_ get exhaustiveness in Go with [external tools],
but it's preferable to have such things in the language IMO.

Many years ago when I was learning Go I wrote a [blog post] about what I liked and disliked
as a Rustacean learning Go. Since then, I've spent a lot more time with Go, and I've learned to like each Go design decision that I initially
disliked, _except_ for the lack of sum types. Most of my issues arose from "trying to program Rust in Go",
i.e. using idioms that are natural to Rust (or other languages I'd used previously). Once I got used to the
programming style, I realized that aside from the lack of sum types I really didn't find much missing
from the language. Perhaps improvements to error handling.

Now, my intention here isn't really to sell sum types. They're somewhat controversial for Go, and
there are good arguments on both sides. You can see one discussion on this topic [here][go-sum-types-issue].
If I were to make a more concrete proposal I'd probably try to motivate this in much more depth. But even
I'm not very _strongly_ of the opinion that Go needs sum types; I have a slight preference for it.

Instead, I'm going to try and sketch this proposal for sum types that has been floating around my
mind for a while. I end up mentioning it often and it's nice to have something to link to. Overall,
I think this "fits well" with the existing Go language design.

 [blog post]: http://inpursuitoflaziness.blogspot.in/2015/02/thoughts-of-rustacean-learning-go.html
 [go-sum-types-issue]: https://github.com/golang/go/issues/19412
 [external tools]: https://github.com/haya14busa/gosum

## The proposal

The essence is pretty straightforward: Extend interfaces to allow for "closed interfaces". These are
interfaces that are only implemented for a small list of types.

Writing the `Foo` sum type above would be:

```go
type Foo interface {
    SomeFunction()
    OtherFunction()
    for string, int
}
```

It doesn't even need to have functions defined on it.

The interface functions can only be called if you have an interface object; they are not directly available
on variant types without explicitly casting (`Foo("...").SomeFunction()`).

(I'm not strongly for the `for` keyword syntax, it's just a suggestion. The core idea is that
you define an interface and you define the types it closes over. Somehow.)

A better example would be an interface for a message-passing system for Raft:

```go
type VoteRequest struct {
    CandidateId uint
    Term uint
    // ...
}

type VoteResponse struct {
    Term uint
    VoteGranted bool
    VoterId uint
}

type AppendRequest struct {
    //...
}

type AppendResponse struct {
    //...
}
// ...
type RaftMessage interface {
    for VoteRequest, VoteResponse, AppendRequest, AppendResponse
}
```

Now, you use type switches for dealing with these:

```go
switch value := msg.(type) {
    case VoteRequest:
        if value.Term <= me.Term {
            me.reject_vote(value.CandidateId)
        } else {
            me.accept_vote(value.CandidateId, value.Term)
        }
    case VoteResponse: // ...
    case AppendRequest: // ...
    case AppendResponse: // ...
}
```

There is no need for the default case, unless you wish to leave one or more of the cases out.

Ideally, these could be implemented as inline structs instead of using dynamic dispatch. I'm not sure
what this entails for the GC design, but I'd love to hear thoughts on this.

We also make it possible to add methods to closed interfaces. This is in the spirit of
[this proposal][proposal-interface-methods], where you allow


 [proposal-interface-methods]: https://github.com/golang/go/issues/16254


```go
func (message RaftMessage) Process(me Me) error {
    // message handling logic
}
```

for closed interfaces.

This aligns more with how sum types are written and used in other languages; instead of assuming
that each method will be a `switch` on the variant, you can write arbitrary code that _may_ `switch`
on the type but it can also just call other methods. This is really nice because you can write
methods in _both_ ways -- if it's a "responsibility of the inner type" kind of method, require it in
the interface and delegate it to the individual types. If it's a "responsibility of the interface"
method, write it as a method on the interface as a whole. I kind of wish Rust had this, because in Rust
you sometimes end up writing things like:

```rust
match foo {
    Foo::Stringy(s) => s.process(),
    Foo::Numerical(n) => n.process(),
    // ...
}
```

Yes, this would work better as a trait, but then you lose some niceties of Rust enums. With this
proposal Go can have it both ways.



------


Anyway, thoughts? This is a really rough proposal, and I'm not sure how receptive other Gophers will be
to this, nor how complex its implementation would be. I don't really intend to submit this as a formal proposal,
but if someone else wants to they are more than welcome to build on this idea.

