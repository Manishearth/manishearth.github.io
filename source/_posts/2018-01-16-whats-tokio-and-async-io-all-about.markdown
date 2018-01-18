---
layout: post
title: "What are Tokio and Async IO all about?"
date: 2018-01-10 14:16:43 +0530
comments: true
categories: [rust, programming, mozilla]
---

The Rust community lately has been focusing a lot on "async I/O" through the [tokio]
project. This is pretty great!

But for many in the community who haven't worked with web servers and related things it's pretty
confusing as to what we're trying to achieve there. When this stuff was being discussed around 1.0,
I was pretty lost as well, having never worked with this stuff before.


What's all this Async I/O business about? What are coroutines? Lightweight threads? Futures? How
does this all fit together?


## What problem are we trying to solve?

One of Rust's key features is "fearless concurrency". But the kind of concurrency required for handling a
large amount of I/O bound tasks -- the kind of concurrency found in Go, Elixir, Erlang -- is absent
from Rust.

Let's say you want to build something like a web service. It's going to be handling thousands of
requests at any point in time (known as the "[c10k] problem"). In general, the problem we're
considering is having a huge number of I/O bound (usually network I/O) tasks.

"Handling N things at once" is best done by using threads. But ... _thousands_ of threads? That
sounds a bit much. Threads can be pretty expensive: Each thread needs to allocate a large stack,
setting up a thread involves a bunch of syscalls, and context switching is expensive.

Of course, thousands of threads _all doing work_ at once is not going to work anyway. You only
have a fixed number of cores, and at any one time only one thread will be running on a core.

But for cases like web servers, most of these threads won't be doing work. They'll be waiting on the
network. Most of these threads will either be listening for a request, or waiting for their response
to get sent.

With regular threads, when you perform a blocking I/O operation, the syscall returns control
to the kernel, which won't yield control back, because the I/O operation is probably not finished.
Instead, it will use this as an opportunity to swap in a different thread, and will swap the original
thread back when its I/O operation is finished (i.e. it's "unblocked"). Without Tokio and friends,
this is how you would handle such things in Rust. Spawn a million threads; let the OS deal with
scheduling based on I/O.

But, as we already discovered, threads don't scale well for things like this[^1].

We need "lighter" threads.

 [c10k]: https://en.wikipedia.org/wiki/C10k_problem
 [^1]: Note that this isn't necessarily true for _all_ network server applications. For example, Apache uses OS threads. OS threads are often the best tool for the job.

## Lightweight threading

I think the best way to understand lightweight threading is to forget about Rust for a moment
and look at a language that does this well, Go.


So instead, Go has lightweight threads, called "goroutines". You spawn these with the `go`
keyword. A web server might do something like this:

```go
listener, err = net.Listen(...)
// handle err
for {
    conn, err := listener.Accept()
    // handle err

    // spawn goroutine:
    go handler(conn)
}
```

This is a loop which waits for new TCP connections, and spawns a goroutine with the connection
and the function `handler`. Each connection will be a new goroutine, and the goroutine will shut down
when `handler` finishes. In the meantime, the main loop continues executing, because it's running in
a different goroutine.

So if these aren't "real" (operating system) threads, what's going on?

A goroutine is an example of a "lightweight" thread. The operating system doesn't know about these,
it sees N threads owned by the Go runtime, and the Go runtime maps M goroutines onto them[^2], swapping
goroutines in and out much like the operating system scheduler. It's able to do this because
Go code is already interruptible for the GC to be able to run, so the scheduler can always ask goroutines
to stop. The scheduler is also aware of I/O, so when a goroutine is waiting on I/O it yields to the scheduler.

Essentialy, a compiled Go function will have a bunch of points scattered throughout it where it
tells the scheduler and GC "take over if you want" (and also "I'm waiting on stuff, please take
over").

When a goroutine is swapped on an OS thread, some registers will be saved, and
the program counter will switch to the new goroutine.

But what about its stack? OS threads have a large stack with them, and you kinda need a stack for functions
and stuff to work.

What Go used to do was segmented stacks. The reason a thread needs a large stack is that most
programming languages, including C, expect the stack to be contiguous, and stacks can't just be
"reallocated" like we do with growable buffers since we expect stack data to stay put so that
pointers to stack data to continue to work. So we reserve all the stack we think we'll ever need
(~8MB), and hope we don't need more.

But the expectation of stacks being contiguous isn't strictly necessary. In Go, stacks are made of tiny
chunks. When a function is called, it checks if there's enough space on the stack for it to run, and if not,
allocates a new chunk of stack and runs on it. So if you have thousands of threads doing a small amount of work,
they'll all get thousands of tiny stacks and it will be fine.

These days, Go actually does something different; it [copies stacks]. I mentioned that stacks can't
just be "reallocated" we expect stack data to stay put. But that's not necessarily true &mdash;
because Go has a GC it knows what all the pointers are _anyway_, and it can rewrite pointers to
stack data on demand.

Either way, Go's rich runtime lets it handle this stuff well. Goroutines are super cheap, and you can spawn
thousands without your computer having problems.


Rust _used_ to support lightweight/"green" threads (I believe it used segmented stacks). However, Rust cares
a lot about not paying for things you don't use, and this imposes a penalty on all your code even if you
aren't using green threads, and it was removed pre-1.0.

 [tokio]: https://github.com/tokio-rs/
 [^2]: Lightweight threading is also often called M:N threading (also "green threading")
 [copies stacks]: https://blog.cloudflare.com/how-stacks-are-handled-in-go/


## Async I/O

A core building block of this is Async I/O. As mentioned in the previous section,
with regular blocking I/O, the moment you request I/O your thread will not be allowed to run
("blocked") until the operation is done. This is perfect when working with OS threads (the OS
scheduler does all the work for you!), but if you have lightweight threads you instead want to
replace the lightweight thread running on the OS thread with a different one.

Instead, you use non-blocking I/O, where the thread queues a request for I/O with the OS and continues
execution. The I/O request is executed at some later point by the kernel. The thread then needs to ask the
OS "Is this I/O request ready yet?" before looking at the result of the I/O.

Of course, repeatedly asking the OS if it's done can be tedious and consume resources. This is why
there are system calls like [`epoll`]. Here, you can bundle together a bunch of unfinished I/O requests,
and then ask the OS to wake up your thread when _any_ of these completes. So you can have a scheduler
thread (a real thread) that swaps out lightweight threads that are waiting on I/O, and when there's nothing
else happening it can itself go to sleep with an `epoll` call until the OS wakes it up (when one of the I/O
requests completes).

(The exact mechanism involved here is probably more complex)

So, bringing this to Rust, Rust has the [mio] library, which is a platform-agnostic
wrapper around non-blocking I/O and tools like epoll/kqueue/etc. It's a building block; and while
those used to directly using `epoll` in C may find it helpful, it doesn't provide a nice programming
model like Go does. But we can get there.


 [`epoll`]: https://en.wikipedia.org/wiki/Epoll
 [mio]: https://github.com/carllerche/mio


## Futures

These are another building block. A [`Future`] is the promise of eventually having a value
(in fact, in Javascript these are called `Promise`s).

So for example, you can ask to listen on a network socket, and get a `Future` back  (actually, a
`Stream`, which is like a future but for a sequence of values). This `Future` won't contain the
response _yet_, but will know when it's ready. You can `wait()` on a `Future`, which will block
until you have a result, and you can also `poll()` it, asking it if it's done yet (it will give you
the result if it is).

Futures can also be chained, so you can do stuff like `future.then(|result| process(result))`.
The closure passed to `then` itself can produce another future, so you can chain together
things like I/O operations. With chained futures, `poll()` is how you make progress; each time
you call it it will move on to the next future provided the existing one is ready.

This is a pretty good abstraction over things like non-blocking I/O.

Chaining futures works much like chaining iterators. Each `and_then` (or whatever combinator)
call returns a struct wrapping around the inner future, which may contain an additional closure.
Closures themselves carry their references and data with them, so this really ends up being
very similar to a tiny stack!

 [`Future`]: https://docs.rs/futures/0.1.17/futures/future/trait.Future.html


## 🗼 Tokio 🗼

Tokio's essentially a nice wrapper around mio that uses futures. Tokio has a core
event loop, and you feed it closures that return futures. What it will do is
run all the closures you feed it, use mio to efficiently figure out which futures
are ready to make a step[^3], and make progress on them (by calling `poll()`).

This actually is already pretty similar to what Go was doing, at a conceptual level.
You have to manually set up the Tokio event loop (the "scheduler"), but once you do
you can feed it tasks which intermittently do I/O, and the event loop takes
care of swapping over to a new task when one is blocked on I/O. A crucial difference is
that Tokio is single threaded, whereas the Go scheduler can use multiple OS threads
for execution. However, you can offload CPU-critical tasks onto other OS threads and
use channels to coordinate so this isn't that big a deal.

While at a conceptual level this is beginning to shape up to be similar to what we had for Go, code-
wise this doesn't look so pretty. For the following Go code:

```go
// error handling ignored for simplicity

func foo(...) ReturnType {
    data := doIo()
    result := compute(data)
    moreData = doMoreIo(result)
    moreResult := moreCompute(data)
    // ...
    return someFinalResult
}
```

The Rust code will look something like

```rust
// error handling ignored for simplicity

fn foo(...) -> Future<ReturnType, ErrorType> {
    do_io().and_then(|data| do_more_io(compute(data)))
          .and_then(|more_data| do_even_more_io(more_compute(more_data)))
    // ......
}
```


Not pretty. [The code gets worse if you introduce branches and loops][loop-fn]. The problem is that in Go we
got the interruption points for free, but in Rust we have to encode this by chaining up combinators
into a kind of state machine. Ew.

 [^3]: In general future combinators aren't really aware of tokio or even I/O, so there's no easy way to ask a combinator "hey, what I/O operation are you waiting for?". Instead, with Tokio you use special I/O primitives that still provide futures but also register themselves with the scheduler in thread local state. This way when a future is waiting for I/O, Tokio can check what the recentmost I/O operation was, and associate it with that future so that it can wake up that future again when `epoll` tells it that that I/O operation is ready.
 [loop-fn]: http://alexcrichton.com/futures-rs/futures/future/fn.loop_fn.html#examples

## Generators and async/await

This is where generators (also called coroutines) come in.

[Generators] are an experimental feature in Rust. Here's an example:

```rust
let mut generator = || {
    let i = 0;
    loop {
        yield i;
        i += 1;
    }
};
assert_eq!(generator.resume(), GeneratorState::Yielded(0));
assert_eq!(generator.resume(), GeneratorState::Yielded(1));
assert_eq!(generator.resume(), GeneratorState::Yielded(2));
```

Functions are things which execute a task and return once. On the other hand, generators
return multiple times; they pause execution to "yield" some data, and can be resumed
at which point they will run until the next yield. While my example doesn't show this, generators
can also finish executing like regular functions.

Closures in Rust are
[sugar for a struct containing captured data, plus an implementation of one of the `Fn` traits to make it callable][closure-huon].

Generators are similar, except they implement the `Generator` trait[^5], and usually store an enum representing various states.

The [unstable book] has some examples on what the generator state machine enum will look like.

This is much closer to what we were looking for! Now our code can look like this:

```rust
fn foo(...) -> Future<ReturnType, ErrorType> {
    let generator = || {
        let mut future = do_io();
        let data;
        loop {
            // poll the future, yielding each time it fails,
            // but if it succeeds then move on
            match future.poll() {
                Ok(Async::Ready(d)) => { data = d; break },
                Ok(Async::NotReady(d)) => (),
                Err(..) => ...
            };
            yield future.polling_info();
        }
        let result = compute(data);
        // do the same thing for `doMoreIo()`, etc
    }

    futurify(generator)
}
```

where `futurify` is a function that takes a generator and returns a future which on
each `poll` call will `resume()` the generator, and return `NotReady` until the generator
finishes executing.

But wait, this is even _more_ ugly! What was the point of converting our relatively
clean callback-chaining code into this mess?

Well, if you look at it, this code now looks _linear_. We've converted our callback
code to the same linear flow as the Go code, however it has this weird loop-yield boilerplate
and the `futurify` function and is overall not very neat.

And that's where [futures-await] comes in. `futures-await` is a procedural macro that
does the last-mile work of packaging away this boilerplate. It essentially lets you write
the above function as


```rust
#[async]
fn foo(...) -> Result<ReturnType, ErrorType> {
    let data = await!(do_io());
    let result = compute(data);
    let more_data = await!(do_more_io());
    // ....
```

Nice and clean. Almost as clean as the Go code, just that we have explicit `await!()` calls. These
await calls are basically providing the same function as the interruption points that Go code
gets implicitly.

And, of course, since it's using a generator under the hood, you can loop and branch and do whatever
else you want as normal, and the code will still be clean.


 [Generators]: https://doc.rust-lang.org/nightly/unstable-book/language-features/generators.html
 [closure-huon]: http://huonw.github.io/blog/2015/05/finding-closure-in-rust/
 [unstable book]: https://doc.rust-lang.org/nightly/unstable-book/language-features/generators.html#generators-as-state-machines
 [futures-await]: https://github.com/alexcrichton/futures-await
 [^5]: The `Generator` trait has a `resume()` function which you can call multiple times, and each time it will return any yielded data or tell you that the generator has finished running.

## Tying it together

So, in Rust, futures can be chained together to provide a lightweight stack-like system. With async/await,
you can neatly write these future chains, and `await` provides explicit interruption points on each I/O operation.
Tokio provides an event loop "scheduler" abstraction, which you can feed async functions to, and under the hood it
uses mio to abstract over low level non-blocking I/O primitives.

These are components which can be used independently &mdash; you can use tokio with futures without
using async/await. You can use async/await without using Tokio. For example, I think this would be
useful for Servo's networking stack. It doesn't need to do _much_ parallel I/O (not at the order
of thousands of threads), so it can just use multiplexed OS threads. However, we'd still want
to pool threads and pipeline data well, and async/await would help here.


Put together, all these components get something almost as clean as the Go stuff, with a little more
explicit boilerplate. Because generators (and thus async/await) play nice with the borrow checker
(they're just enum state machines under the hood), Rust's safety guarantees are all still in play,
and we get to have "fearless concurrency" for programs having a huge quantity of I/O bound tasks!

_Thanks to Arshia Mufti, Steve Klabnik, Zaki Manian, and Kyle Huey for reviewing drafts of this post_
