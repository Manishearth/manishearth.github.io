---
layout: post
title: "Prolonging temporaries in Rust"
date: 2017-04-13 13:36:05 +0800
comments: true
categories: rust mozilla programming
---

A colleague of mine learning Rust had an interesting type / borrow checker error. The solution needs
a less-used feature of Rust (which basically exists precisely for this kind of thing), so I thought
I'd document it.

The code was like this:

```rust
let maybe_foo = if some_condition {
    thing.get_ref() // returns Option<&Foo>, borrowed from `thing`
} else {
    thing.get_owned() // returns Option<Foo>
};

use(maybe_foo);
```

If you want to follow along, here is a full program that does this ([playpen][pp-1]):

```rust
#[derive(Debug)]
struct Foo;

struct Thingy {
    foo: Foo
}

impl Thingy {
    pub fn get_ref(&self) -> Option<&Foo> {
        Some(&self.foo)
    }
    pub fn get_owned(&self) -> Option<Foo> {
        Some(Foo)
    }
    pub fn new() -> Self {
        Thingy {
            foo: Foo
        }
    }
}



pub fn main() {
    let some_condition = true;
    let thing = Thingy::new();

    let maybe_foo = if some_condition {
        thing.get_ref() // returns Option<&Foo>, borrowed from `thing`
    } else {
        thing.get_owned() // returns Option<Foo>
    };
    
    println!("{:?}", maybe_foo);
}
```

[pp-1]: https://play.rust-lang.org/?gist=e09a79b511e347fe786e4689d282b806&version=stable&backtrace=0

I'm only going to be changing the contents of `main()` here.

What's happening here is that a non-`Copy` type, `Foo`, is returned in an `Option`. In one case,
we have a reference to the `Foo`, and in another case an owned copy.

We want to set a variable to these, but of course we can't because they're different types.

In one case, we have an owned `Foo`, and we can usually obtain a borrow from an owned type. For
`Option`, there's a convenience method `.as_ref()` that does this[^1]. Let's try using that ([playpen][pp-2]):

```rust
let maybe_foo = if some_condition {
    thing.get_ref()
} else {
    thing.get_owned().as_ref()
};
```

 [pp-2]: https://play.rust-lang.org/?gist=41c3f836b9485c216ccb05c257ae5326&version=stable&backtrace=0
 [^1]: In my experience `.as_ref()` is the solution to many, many borrow check issues newcomers come across, especially those involving `.map()`

This will give us an error.

```
error: borrowed value does not live long enough
  --> <anon>:32:5
   |
31 |         thing.get_owned().as_ref()
   |         ----------------- temporary value created here
32 |     };
   |     ^ temporary value dropped here while still borrowed
...
35 | }
   | - temporary value needs to live until here

error: aborting due to previous error
```

The problem is, `thing.get_owned()` returns an owned value. There's nothing that it gets anchored to
(we don't set its value to a variable), so it is just a temporary -- we can call methods on it, but
once we're done the value will go out of scope.

What we want is something like

```rust
let maybe_foo = if some_condition {
    thing.get_ref()
} else {
    let owned = thing.get_owned();
    owned.as_ref()
};
```

but this will still give a borrow error -- `owned` will still go out of scope within the `if` block,
and we need the reference to it last as long as `maybe_foo` (outside the block) is supposed to last.

So this is no good.

An alternate solution here _can_ be copying/cloning the `Foo` in the _first_ case by calling `.map(|x|
x.clone())` or `.cloned()` or something. Sometimes you don't want to clone, so this isn't great.

Another solution here -- the generic advice for dealing with values which may be owned or borrow --
is to use `Cow`. It does incur a runtime check, though; one which can be optimized out if things are
inlined enough.

What we need to do here is to extend the lifetime of the temporary returned by `thing.get_owned()`.
We need to extend it _past_ the scope of the `if`.

One way to do this is to have an `Option` outside that scope which we mutate ([playpen][pp-3]).

```rust
let mut owned = None;
let maybe_foo = if some_condition {
    thing.get_ref()
} else {
    owned = thing.get_owned();
    owned.as_ref()
};
```

 [pp-3]: https://play.rust-lang.org/?gist=7868045f2cebec6d23e7a065f5823767&version=stable&backtrace=0

This works in this case, but in this case we already had an `Option`. If `get_ref()` and `get_owned()`
returned `&Foo` and `Foo` respectively, then we'd need to do something like:

```rust
let mut owned = None;
let maybe_foo = if some_condition {
    thing.get_ref()
} else {
    owned = Some(thing.get_owned());
    owned.as_ref().unwrap()
};
```

which is icky since it introduces an unwrap.


What we really need is a way to signal to the compiler that it needs to hold on to that temporary
for the scope of the enclosing block.

We can do that! ([playpen][pp-4])


```rust
let owned; // 😯😯😯😯😯
let maybe_foo = if some_condition {
    thing.get_ref()
} else {
    owned = thing.get_owned();
    owned.as_ref()
};
```

 [pp-4]: https://play.rust-lang.org/?gist=1ddf2a428e73b01baa72acdad7cbbf2b&version=stable&backtrace=0

We know that Rust doesn't do "uninitialized" variables. If you want to name a variable, you have to
initialize it. `let foo;` feels rather like magic in this context, because it looks like we've declared
an uninitialized variable.

What's less well known is that Rust _can_ do "deferred" initialization. Here, you declare a variable
and can initialize it later, but expressions involving the variable can only exist in branches
where the compiler knows it has been initialized.

This is the case here. We declared the `owned` variable beforehand. It now lives in the outer scope
and won't be destroyed until the end of the outer scope. However, the variable cannot be used directly
in an expression in the first branch, or after the `if`. Doing so will give a compile time error
saying ```use of possibly uninitialized variable: `owned` ```. We can only use it in the `else` branch
because the compiler can see that it is unconditionally initialized in that branch.

We can still read the value of `owned` indirectly through `maybe_foo` from outside the branch.
This is okay because the storage of `owned` is guaranteed to live as long as the outer scope,
and `maybe_foo` borrows from it. The only time `maybe_foo` is set to a value inside `owned` is when
`owned` has been initialized, so it is safe.
