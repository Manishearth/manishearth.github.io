---
layout: post
title: "Why I enjoy blogging"
date: 2018-08-23 14:16:43 -0700
comments: true
categories: [writing, programming]
---

I started this blog three years ago, moving from my [older blog][blogspot], hoping to talk about programming, math, physics, books, and miscellenia. I've not quite talked about everything I wanted to, but I've been very very happy with the experience of blogging. `wc` says I've written almost 75k words, which is mind-boggling to me!

I often get asked by others &mdash; usually trying to decide if they should start blogging &mdash; what it's like. I also often try to convince friends to blog by enumerating why I think it's awesome. Might as well write it down so that it's generally useful for everyone! 😃



 [blogspot]: http://inpursuitoflaziness.blogspot.com/


## Blogging helps cement my understanding of things!

I've often noticed that I'll start blogging about something I _think_ I understand, and it turns out that my understanding of the subject was somewhat nebulous. Turns out it's pretty easy to convince ourselves that we understand something.

The act of writing stuff down helps cement my own understanding &mdash; words are usually not as nebulous as thoughts so I'm forced to figure out little details.

I recall when I wrote my post on [how Rust's thread safety guarantees work][rust-threads]. I _thought_ I understood `Send` and `Sync` in Rust &mdash; I understood what they did, but I didn't have a clear mental model for them. I obtained this mental model through the process of writing the post; to be able to explain it to others I had to first explain it to myself.

I point out this post in particular because this was both one of the first posts for me where I'd noticed this, and, more importantly, my more concrete mental model led to me [finding a soundness bug in Rust's standard library][scopedkey]. When I was thinking about my mental model I realized "an impl that looks like this should never exist",
and I grepped the source code and found one.

I've even noticed a difference between one-on-one explaining and explaining things through blog posts. I _love_ explaining things one-on-one, it's much easier to tailor the explanation to the other person's background,
as well as what they're actually asking for help with. Plus, it's interactive. A_lot_ of my posts are of the "okay I get this question a lot I'm going to write down the answer so I don't have to repeat myself" kind and I've found that I've often learned things from these despite having talked about the thing in the article contents multiple times.

I guess it's basically that blogging is inherently one-many &mdash; you're trying to explain to a whole group of people with varied backgrounds &mdash; which means you need to cover all your bases[^3] and explain everything together instead of the minimum necessary.

 [rust-threads]: https://manishearth.github.io/blog/2015/05/30/how-rust-achieves-thread-safety/
 [scopedkey]: https://github.com/rust-lang/rust/issues/25894
 [^3]: Incidentally, I find there's a similar dynamic when it comes to forum discussions vs hashing things out one-on-one, it's way harder to get anywhere with forum discussions because they're one-many and you have to put in that much more work to empathize with everyone else and also phrase things in a way that is resilient to accidental misinterpretation.


## It's really fun to revisit old posts!

Okay, I'll admit that I never really write blog posts with this in mind. But when I _do_ reread them, I'm usually quite thankful I wrote them!

I'm a fan of rereading in general, I've reread most of my favorite books tens of times; I make a yearly pilgrimage to [James Mickens' website][mickens]; I reread many of my favorite posts and articles on the internet; and I often reread my _own_ posts from the past.

Sometimes I'll do it because I want a refresher in a topic. Sometimes I'll do it because I'm bored. Whatever the reason, it's always been a useful and fun thing to do.

Rereading old posts is a great way to transport myself back to my mindset from when I wrote the post. It's easy to see progress in my understanding of things as well as in my writing. It's interesting to note what I thought super important to include in the post _then_ that I consider totally obvious _now_[^5]. It's interesting to relearn what I've forgotten. It's reassuring to realize that my terrible jokes were just as terrible as they are now.

One of my favorite posts to reread is [this really long one on generalized zero knowledge proofs][zkp-blog]. It's the longest post I've written so far[^6], and it's on a topic I don't deal with often &mdash; cryptography. Not only does it help put me back in a mindset for thinking about cryptography, it's about something super interesting but also complicated enough that rereading the post is like learning it all over again.



 [mickens]: https://mickens.seas.harvard.edu/wisdom-james-mickens
 [^5]: This is especially important as I get more and more "used" to subjects I'm familiar with -- it's easy to lose the ability to explain things when I think half of it is obvious.
 [zkp-blog]: https://manishearth.github.io/blog/2016/03/05/exploring-zero-knowledge-proofs/
 [^6]: This is probably the _real_ reason I love rereading it &mdash; I like being verbose and would nest parentheses and footnotes if society let me

## It lets me exercise a different headspace!

I like programming a lot, but if programming was _all_ I did, I'd get tired pretty quickly. When I was a student learning physics I'd often contribute to open source in my spare time, but now I write code full time so I'm less inclined to do it in my free time[^8].

But I still sometimes feel like doing programmery things in my spare time just ... not programming.

Turns out that blogging doesn't tire me out the same way! I'm sure that if I spent the whole day writing I'd not want to write when I go home, but I don't spend the whole day writing, so it's all good. It's refreshing to sit down to write a blog post and discover a fresh reserve of energy. I'm not sure if this is the right term, but I usually call this "using a different headspace".

I've also started using this to plan my work, I mix up the kinds of headspace I'm employing for various tasks so that I feel energetic throughout the day.

This is also why I really enjoy mentoring &mdash; mentoring often requires the same effort from me as fixing it myself, but it's a different headspace I'm employing so it's less tiring.


 [^8]: I also am in general less inclined to do technical things in my free time and have a better work-life balance, glad that worked out!

## Blogging lets me be lazy!

I often find myself explaining things often. I like helping folks and explaining things, but I'm also lazy[^1], so writing stuff down really makes stuff easy for me! If folks ask me a question I can give a quick answer and then go "if you want to learn more, I've written about it here!". If folks are asking a question a lot, there's probably something missing in the documentation or learning materials about it. Some things can be fixed upstream in documentation, but other things &mdash; like ["how should I reason about modules in Rust?"][rust-modules] deserve to be tackled as a separate problem and addressed with their own post.


(Yes, this post is in this category!)


 [^1]: See blog title
 [rust-modules]: https://manishearth.github.io/blog/2017/05/14/mentally-modelling-modules/


## It's okay if folks have written about it before!

A common question I've gotten is "Well I can write about X but ... there are a lot of other posts out there about it, should I still?"

Yes!!

People think differently, people learn differently, and people come from different backgrounds. Existing posts may be useful for some folks but less useful for others.

My personal rule of thumb is that if it took _me_ some effort to understand something after reading about it, that's something worth writing about, so it's easier to understand for others like me encountering the subject.

One of my favorite bloggers, [Julia Evans] very often writes posts explaining computer concepts. Most of the times these have been explained before in other blog posts or manuals. But that doesn't matter &mdash; her posts are _different_, and they're _amazing_. They're upbeat, fun to read, and often get me excited to learn more about things I knew about but never really looked at closely before.


 [Julia Evans]: https://jvns.ca/

## I kinda feel it's my duty to?

There's a quote by Toni Morrison I quite enjoy:

> I tell my students, 'When you get these jobs that you have been so brilliantly trained for, just remember that your real job is that if you are free, you need to free somebody else. If you have some power, then your job is to empower somebody else. This is not just a grab-bag candy game.

I enjoy it so much I [concluded my talk at RustFest Kyiv with it][rustfest-slides]!

I have the privilege of having time to do things like blogging and mentoring. Given that I feel that it really is my duty to share what I know as much as possible; to help others attempting to tread the path I'm treading; and to battle against tribal knowledge.

When it comes to programming I'm mostly "self-taught". But when I say that, I really mean that I wasn't taught in a traditional way by other humans &mdash; I learned things by trying stuff out and _reading what others had written_. I didn't learn Rust by taking `rustc` and pretending to be a fuzzer and just trying random nonsense till stuff made sense, I went through the tutorial (and _then_ started exploring by trying random stuff). I didn't figure out cool algorithms by discovering them from first principles, I picked them up from books and blog posts.

This means that for me, personally, knowledge-sharing is especially important. If I had to spend time figuring something out, I should make it easier for the next people to try[^10].

(All this said, I probably don't blog as much as I _should_)

 [rustfest-slides]: https://manishearth.github.io/rustfest-slides/#/13
 [^10]: One of my former title ideas for this post was "Knowledge is Theft", riffing off of this concept, but that was a bit too tongue-in-cheek.


## You should blog too!

I wish everyone wrote more. I know not everyone has the time/privilege to do this, but if you do, I urge you to start!

I feel like tips on _how_ to blog would fill up an entire other blog post, but Julia Evans has [multiple][jvns-1] [posts][jvns-2] on this that I strongly recommend. Feel free to ask me for review on posts!

As for the technicalities of setting up a blog, my colleague Emily recently [wrote a great post about doing this with Jekyll][emilykager-post]. This blog uses [Octopress] which is similar to set up.


_Thanks to [Arshia Mufti][arshia], ......... for reviewing drafts of this blog post._



 [jvns-1]: https://jvns.ca/blog/2016/05/22/how-do-you-write-blog-posts//
 [jvns-2]: https://jvns.ca/blog/2017/03/20/blogging-principles/
 [emilykager-post]: https://www.emilykager.com/writing/2018/07/27/myo-website.html
 [Octopress]: http://octopress.org
 [arshia]: https://twitter.com/arshia__