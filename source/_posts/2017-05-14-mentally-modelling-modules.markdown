---
layout: post
title: "Mentally modelling modules"
date: 2017-05-14 19:38:15 -0700
comments: true
categories: programming rust mozilla tidbits
---

_Note: This post was written before the Rust 2018 edition, and does not yet incorporate the [changes made to the module system][module-changes]._


The module and import system in Rust is sadly one of the many confusing things you have to deal with whilst
learning the language. A lot of these confusions stem from a misunderstanding of how it works.
In explaining this I've seen that it's usually a common set of misunderstandings.

In the spirit of ["You're doing it wrong"][wrongwrongwrong], I want to try and explain one
"right" way of looking at it. You can go pretty far[^1] without knowing this, but it's useful
and helps avoid confusion.


 [module-changes]: https://doc.rust-lang.org/edition-guide/rust-2018/module-system/index.html
 [wrongwrongwrong]: http://manishearth.github.io/blog/2017/04/05/youre-doing-it-wrong/
 [^1]: This is because most of these misunderstandings lead to a model where you think fewer things compile, which is fine as long as it isn't too restrictive. Having a mental model where you feel more things will compile than actually do is what leads to frustration; the opposite can just be restrictive.


---------

<br>


First off, just to get this out of the way, `mod foo;` is basically a way of saying
"look for `foo.rs` or `foo/mod.rs` and make a module named `foo` with its contents".
It's the same as `mod foo { ... }` except the contents are in a different file. This
itself can be confusing at first, but it's not what I wish to focus on here. The Rust book explains this more
in [the chapter on modules][book-mod].

In the examples here I will just be using `mod foo { ... }` since multi-file examples are annoying,
but keep in mind that the stuff here applies equally to multi-file crates.



 [book-mod]: https://doc.rust-lang.org/book/crates-and-modules.html#multiple-file-crates



### Motivating examples


To start off, I'm going to provide some examples of Rust code which compiles. Some of these may be
counterintuitive, based on your existing model.

```rust
pub mod foo {
    extern crate regex;
    
    mod bar {
        use foo::regex::Regex;
    }
}
```

([playpen](http://play.integer32.com/?gist=7673736a57fe99092446ec73f8b8f555&version=undefined))


```rust
use std::mem;


pub mod foo {
    // not std::mem::transmute!
    use mem::transmute;

    pub mod bar {
        use foo::transmute;
    }
}
```

([playpen](http://play.integer32.com/?gist=49415d74214b07b13c236ce88bdf54aa&version=undefined))

```rust
pub mod foo {
    use bar;
    use bar::bar_inner;

    fn foo() {
        // this works!
        bar_inner();
        bar::bar_inner();
        // this doesn't
        // baz::baz_inner();
        
        // but these do!
        ::baz::baz_inner();
        super::baz::baz_inner();
        
        // these do too!
        ::bar::bar_inner();
        super::bar::bar_inner();
        self::bar::bar_inner();
        
    }
}

pub mod bar {
    pub fn bar_inner() {}
}
pub mod baz {
    pub fn baz_inner() {}
}
```

([playpen](http://play.integer32.com/?gist=547fea76590b6c5dbbb04ccbc89cf8d2&version=undefined))


```rust
pub mod foo {
    use bar::baz;
    // this won't work
    // use baz::inner();
    
    // this will
    use self::baz::inner;
    // or
    // use bar::baz::inner
    
    pub fn foo() {
        // but this will work!
        baz::inner();
    }
}

pub mod bar {
    pub mod baz {
        pub fn inner() {}
    }
}
```

([playpen](http://play.integer32.com/?gist=e553e52d1cbf0d38fd0b42c09ccafe44&version=undefined))



These examples remind me of the "point at infinity" in elliptic curve crypto or fake particles in
physics or fake lattice elements in various fields of CS[^2]. Sometimes, for something to make sense,
you add in things that don't normally exist. Similarly, these examples may contain code which
is not traditional Rust style, but the import system
still makes more sense when you include them.

 [^2]: One example closer to home is how Rust does lifetime resolution. Lifetimes form a lattice with `'static` being the bottom element. There is no top element for lifetimes in Rust syntax, but internally [there is the "empty lifetime"](http://manishearth.github.io/rust-internals-docs/rustc/ty/enum.Region.html#variant.ReEmpty) which is used during borrow checking. If something resolves to have an empty lifetime, it can't exist, so we get a lifetime error.

### Imports

The core confusion behind how imports work can really be resolved by remembering two rules:

 - `use foo::bar::baz` resolves `foo` relative to the root module (`lib.rs` or `main.rs`)
   - You can resolve relative to the current module by explicily trying `use self::foo::bar::baz`
 - `foo::bar::baz` within your code[^3] resolves `foo` relative to the current module
   - You can resolve relative to the root by explicitly using `::foo::bar::baz`


That's actually ... it. There are no further caveats. The rest of this is modelling what
constitutes as "being within a module".

Let's take a pretty standard setup, where `extern crate` declarations are placed in the the root
module:

 [^3]: When I say "within your code", I mean "anywhere but a `use` statement". I may also term these as "inline paths".

```rust
extern crate regex;

mod foo {
    use regex::Regex;

    fn foo() {
        // won't work
        // let ex = regex::Regex::new("");
        let ex = Regex::new("");
    }
}
```

When we say `extern crate regex`, we pull in the `regex` crate into the crate root. This behaves
pretty similar to `mod regex { /* contents of regex crate */}`. Basically, we've imported
the crate into the crate root, and since all `use` paths are relative to the crate root,
`use regex::Regex` works fine inside the module.

Inline in code, `regex::Regex` won't work because as mentioned before inline paths are relative
to the current module. However, you can try `::regex::Regex::new("")`.

Since we've imported `regex::Regex` in `mod foo`, that name is now accessible to everything inside
the module directly, so the code can just say `Regex::new()`.

The way you can view this is that `use blah` and `extern crate blah` create an item named
`blah` "within the module", which is basically something like a symbolic link, saying
"yes this item named `blah` is actually elsewhere but we'll pretend it's within the module"

The error message from this code may further drive this home:

```rust
use foo::replace;

pub mod foo {
    use std::mem::replace;
}
```

([playpen](http://play.integer32.com/?gist=07527a61153519fbf218ffb93f13b3cd&version=undefined))

The error I get is

```
error: function `replace` is private
 --> src/main.rs:3:5
  |
3 | use foo::replace;
  |     ^^^^^^^^^^^^
```

There's no function named `replace` in the module `foo`! But the compiler seems to think there is?

That's because `use std::mem::replace` basically is equivalent to there being something like:


```rust
pub mod foo {
    fn replace(...) -> ... {
        ...
    }

    // here we can refer to `replace` freely (in inline paths)
    fn whatever() {
        // ...
        let something = replace(blah);
        // ...
    }
}
```

except it's actually like a symlink to the function defined in `std::mem`. Because inline paths
are relative to the current module, saying `use std::mem::replace` works as if you had defined
a function `replace` in the same module, and you can refer to `replace()` without needing
any extra qualification in inline paths.

This also makes `pub use` fit perfectly in our model. `pub use` says "make this symlink, but let
others see it too":


```rust
// works now!
use foo::replace;

pub mod foo {
    pub use std::mem::replace;
}
```


------

<br>

Folks often get annoyed when this doesn't work:

```rust
mod foo {
    use std::mem;
    // nope
    // use mem::replace;
}
```

As mentioned before, `use` paths are relative to the root module. There is no `mem`
in the root module, so this won't work. We can make it work via `self`, which I mentioned
before:


```rust
mod foo {
    use std::mem;
    // yep!
    use self::mem::replace;
}
``` 

Note that this brings overloading of the `self` keyword up to a grand total of _four_! Two cases
which occur in the import/path system:

 - `use self::foo` means "find me `foo` within the current module"
 - `use foo::bar::{self, baz}` is equivalent to `use foo::bar; use foo::bar::baz;`
 - `fn foo(&self)` lets you define methods and specify if the receiver is by-move, borrowed, mutably borrowed, or other
 - `Self` within implementations lets you refer to the type being implemented on

Oh well, at least it's not `static`.


------

<br><br>

Going back to one of the examples I gave at the beginning:


```rust
use std::mem;


pub mod foo {
    use mem::transmute;

    pub mod bar {
        use foo::transmute;
    }
}
```

([playpen](http://play.integer32.com/?gist=49415d74214b07b13c236ce88bdf54aa&version=undefined))

It should be clearer now why this works. The root module imports `mem`. Now, from everyone's point
of view, there's an item called `mem` in the root.

Within `mod foo`, `use mem::transmute` works because `use` is relative to the root, and `mem`
already exists in the root! When you `use` something, all child modules will see it as if it were
actually belonging to the module. (Non-child modules won't see it because of privacy, we
saw an example of this already)

This is why `use foo::transmute` works from `mod bar`, too. `bar` can refer to the contents
of `foo` via `use foo::whatever`, since `foo` is a child of the root module, and `use` is relative
to the root. `foo` already has an item named `transmute` inside it because it imported one.
Nothing in the parent module is private from the child, so we can `use foo::transmute` from
`bar`.

Generally, the standard way of doing things is to either not use modules (just a single lib.rs),
or, if you do use modules, put nothing other than `extern crate`s and `mod`s in the root.
This is why we rarely see shenanigans like the above; there's nothing in the root crate
to import, aside from other crates specified by `extern crate`. The trick of
"reimport something from the parent module" is also pretty rare because there's basically no
point to using that (just import it directly!). So this is not the kind of code
you'll see in the wild.

------

<br>


Basically, the way the import system works can be summed up as:

 - `extern crate` and `use` will act as if they were defining the imported item in the current module, like a symbolic link
 - `use foo::bar::baz` resolves the path relative to the root module
 - `foo::bar::baz` in an inline path (i.e. not in a `use`) will resolve relative to the current module
 - `::foo::bar::baz` will _always_ resolve relative to the root module
 - `self::foo::bar::baz` will _always_ resolve relative to the current module
 - `super::foo::bar::baz` will _always_ resolve relative to the parent module

Alright, on to the other half of this. Privacy.



### Privacy

So how does privacy work?

Privacy, too, follows some basic rules:

- If you can access a module, you can access all of its `pub` contents
- A module can always access its child modules, but not recursively
  - This means that a module cannot access private items in its children, nor can it access private grandchildren modules
- A child can always access its parent modules (and their parents), and _all_ their contents
- `pub(restricted)` [is a proposal][pubres] which extends this a bit, but it's experimental so we won't deal with it here


 [pubres]: https://github.com/rust-lang/rfcs/blob/master/text/1422-pub-restricted.md

Giving some examples,

```rust
mod foo {
    mod bar {
        // can access `foo::foofunc`, even though `foofunc` is private

        pub fn barfunc() {}

    }
    // can access `foo::bar::barfunc()`, even though `bar` is private
    fn foofunc() {}
}
```




```rust
mod foo {
    mod bar {
        // We can access our parent and _all_ its contents,
        // so we have access to `foo::baz`. We can access
        // all pub contents of modules we have access to, so we
        // can access `foo::baz::bazfunc`
        use foo::baz::bazfunc;
    }
    mod baz {
        pub fn bazfunc() {}
    }
}
```

It's important to note that this is all contextual; whether or not a particular
path works is a function of where you are. For example, this works[^4]:

```rust
pub mod foo {
    /* not pub */ mod bar {
        pub mod baz {
            pub fn bazfunc() {}
        }
        pub mod quux {
            use foo::bar::baz::bazfunc;
        }
    }
}
```

We are able to write the path `foo::bar::baz::bazfunc` even though `bar` is private!

This is because we still have _access_ to the module `bar`, by being a descendent module.


 [^4]: Example adapted from [this discussion](https://www.reddit.com/r/rust/comments/5m4w95/the_rust_module_system_is_too_confusing/dc1df2z/)


------

<br>


Hopefully this is helpful to some of you. I'm not really sure how this can fit into the official
docs, but if you have ideas, feel free to adapt it[^5]!

 [^5]: Contact me if you have licensing issues; I still have to figure out the licensing situation for the blog, but am more than happy to grant exceptions for content being uplifted into official or semi-official docs.
