---
layout: post
title: "Rust Governance: Scaling Empathy"
date: 2019-02-04 09:40:49 +0100
comments: true
categories: [rust, programming]
---

There's been a lot of talk about improving Rust's governance model lately. As we decompress from last year's hectic edition work, we're slowly starting to look at all the bits of [debt] we accumulated, and [organizational debt] is high on that list.

I've been talking in private with people about a bunch of these things for quite a while now, and I felt it worthwhile to write down as much of my thoughts as I can before the Rust All Hands in Berlin this week.

In the interest of brevity[^1] I'm going to assume the reader is roughly familiar with most of the stuff that's happened with the Rust community in the past few years. I'm probably going to omit concrete examples of incidents, both to avoid mischaracterizing individual actions (as with most such analyses, I wish to talk in more general terms about trends), and also just because it would take me forever to write this if I were to supply all the layers of context. If you feel something is inaccurate, please let me know.

This blog post is probably going to reach the eyes of non-Rust-community members. You're welcome to read it, but please accept my apologies in advance if it doesn't make any sense. This is something that I initially planned to circulate as a private post (writing for a general audience is _hard_), but I felt this would be more widely useful. However due to time constraints I haven't had time to edit it to make it acceptable to a wider audience.

 [debt]: https://twitter.com/ManishEarth/status/1073088515041198080
 [organizational debt]: https://boats.gitlab.io/blog/post/rust-2019/

 [^1]: I am way too verbose for "brief" to be an accurate description of anything I write, but might as well _try_.

## The symptoms

Before I actually get into it, I'd like to carefully delineate _what_ the problem is that I'm talking about. Or more accurately, the _symptoms_ I am talking about &mdash; as I'll explain soon I feel like these are not the actual problem but symptoms of a more general problem.

Basically, as time has gone by our decisionmaking process has become more and more arduous, both for community members and the teams. Folks have to deal with:

 - The same arguments getting brought up over and over again
 - Accusations of bad faith
 - Derailing
 - Not feeling heard
 - Just getting exhausted by all the stuff that's going on

The RFC process is the primary exhibitor of these symptoms, but semi-official consensus-building threads on [internals.rust-lang.org][irlo] have similar problems.

Aaron [has written some extremely empathetic blog posts][listening-and-trust] about a bunch of these problems, starting with concrete examples and ending with a takeaway of a bunch of values for us to apply as well as thoughts on what our next steps can be. I highly recommend you read them if you haven't already.

Fundamentally I consider our problems to be social problems, not technical ones. In my opinion, technical solutions like changing the discussion forum format may be necessary but are not sufficient for fixing this.

 [listening-and-trust]: http://aturon.github.io/2018/05/25/listening-part-1/
 [irlo]: https://internals.rust-lang.org

## The scaling problem

I contend that all of these issues are symptoms of an underlying _scaling issue_, but also a failure of how our moderation works.

The scaling issue is somewhat straightforward. Such forum discussions are inherently N-to-N discussions. When you leave a comment, you're leaving a comment for _everyone_ to read and interpret, and this is hard to get right. It's _much_ easier to have one-on-one discussions because it's easy to build a shared vocabulary and avoid misunderstandings; any misunderstandings can often be quickly detected and corrected.

I find that most unpleasant technical arguments stem from an unenumerated mismatch of assumptions, or sometimes what I call a mismatch of axioms (i.e. when there is fundamental conflict between core beliefs). A mismatch of assumptions, if identified, can be resolved, leading to an amicable conclusion. Mismatches of axioms are harder to resolve, however recognizing them can take most of the vitriol out of an argument, because both parties will _understand_ each other, even if they don't _agree_. In such situations the end result may leave one or both parties _unhappy_, but rarely _angry_. (It's also not necessary that axiom mismatches leave people unhappy, embracing [positive sum thinking] helps us come to mutually beneficial conclusions)

All of these mismatches are easy to identify in one-on-one discussions, because it's easy to switch gears to the meta discussion for a bit.

One-on-one discussions are pleasant. They foster empathy.

N-to-N discussions are _not_. It's harder to converge on this shared vocabulary amongst N other people. It's harder to identify these mismatches, partly because it's hard to switch into the meta-mode of a discussion at all, but also because there's a lot going on. It's harder to build empathy.

As we've grown, discussion complexity has grown quadratically, and we're not really attempting to relinearize them.

 [positive sum thinking]: http://aturon.github.io/2018/06/02/listening-part-2/#pluralism-and-positive-sums

### Hanabi and parallel universes

I quite enjoy the game of [Hanabi]. It's a game of information and trust, and I find it extremely fun, especially with the right group.

Hanabi is a cooperative game. You can see everyone's cards (or tiles) but your own, and information-sharing is severely restricted. The goal is to play the right cards in the right order to collectively win. The gimmick is to share additional information through the side-channel of _the choice of move you make_.

A very common occurrence in this game is that people start making plans in their mind. You typically have a decent understanding of what information everyone has, and you can use this to make predictions as to what everyone's moves will be. With this in mind, you can attempt to "set up" situations where the game progresses rapidly in a short period of time. This is somewhat necessary for the game to work, but a common pitfall is for these plans to be _extremely_ elaborate, leading to frustration as the game doesn't actually play out as planned.

The core issue behind this is forgetting that you actually _can't_ see the entire game state, since your own cards are hidden. It's not just _you_ who has plans &mdash; everyone does! And each of those plans is incomplete since they're missing a piece of the picture, just as you are.

In Hanabi it's very easy to forget that you're missing a piece of the picture &mdash; in competitive card games you mostly can't see the game state since everyone else's cards are hidden. But in Hanabi you can see _most_ of the cards and it's easy to forget that your own four cards are hidden from you.

So what ends up happening is that due to incomplete information, everyone is operating in their own little parallel universe, occasionally getting frustrated when it becomes clear that other players are not operating in the same universe. As long as you recognize the existence of these parallel universes beforehand you're fine, but if you don't you will be frustrated.

This is largely true of N-to-N discussions as well. Because most of what's being said makes sense to an individual in a particular way, it's very easy for them to forget that other people may not share your assumptions and thus may be on a different page. Every time someone leaves a comment, different people may interpret it differently, "forking" the common understanding of the state of the discussion into multiple parallel universes. Eventually there are enough parallel universes that everyone's talking past each other.

One thing I often prefer doing in such cases is to have a one on one discussion with people who disagree with me &mdash; typically the shared understanding that is the end result of such discussions is super useful and can be brought back to the discussion as something that all participants interpret the same way. I'm not consistent in doing this &mdash; in the midst of a heated argument it's easy to get too wrapped up in the argument to think about getting results and I've certainly had my time arguing instead of resolving &mdash; but overall whenever I've chosen to do this it's been a useful policy.

This is a good example of how relinearization and communication can help move N-to-N discussions along. Operating in different parallel universes is kind of the _point_ of Hanabi, but it's not the point of having a technical discussion.

 [Hanabi]: https://en.wikipedia.org/wiki/Hanabi_(card_game)

## The moderation problem

In a technical discussion, broadly speaking, I find that there are three kinds of comments disagreeing with you:

 - Constructive: Comments which disagree with you constructively. We're glad these exist, disagreement can hurt but is necessary for us to collaboratively reach the best outcomes.
 - Disruptive: Comments which may be written in good faith but end up being disruptive. For example, this includes people who don't read enough of the discussion and end up rehashing the same points. It also includes taking discussions off topic. These kinds of things are problematic but not covered by the code of conduct.
 - Abrasive: Comments which are rude/abrasive. These are covered by the code of conduct. The mod team tries to handle these.

(For a long time I and [Aaron] had a shared vocabulary of "Type A, B, C" for these, mostly because I'm often unimaginative when it comes to such things, thanks to [Mark] for coming up with, better, descriptive titles)

Note that while I'm talking about "disruptive" comments it's not a judgement on the _intent_ of the participants, but rather a judgement on the harm it has caused.

The second category -- disruptive comments -- are the thing we're currently unable to handle well. They snowball pretty badly too &mdash; as more and more of these collect, more and more people get frustrated and in turn leave comments that cause further disruption. As the discussion progresses into more and more "parallel universes" it also just becomes _easier_ for a comment to be disruptive.

The Rust moderation team operates mostly passively, we simply don't have the scale[^2] to watch for and nip these things in the bud. Active moderation requires a degree of involvement we cannot provide. So while the best response would be to work with participants and resolve issues early as we see them crop up, we typically get pulled in at a point where some participants are already causing harm, and our response has to be more severe. It's a bit of a catch-22: it's not exactly our job to deal with this stuff[^3], but by the time it _becomes_ our job (or even, by the time we _notice_), most acceptable actions for us to take are extremely suboptimal. The problem with passive moderation is that it's largely reactive &mdash; it's harder to proactively nudge the discussion in the right direction when you don't even _notice_ what's going on until it's too late. This is largely okay for dealing with bad-faith actors (the main goal of the mod team); it's hard to _prevent_ someone from deciding to harass someone else. But for dealing with disruptive buildups, we kind of need something different.



 [Aaron]: http://twitter.com/aaron_turon/
 [Mark]: https://github.com/mark-simulacrum
 [^2]: Scaling the moderation team properly is another piece of this puzzle that I'm working on; we've made some progress recently.
 [^3]: I helped draft [our moderation policy](https://www.rust-lang.org/policies/code-of-conduct#moderation), so this is a somewhat a lack of foresight on my part, but as I'll explain later it's suboptimal for the mod team to be dealing with this anyway.

## Participation guidelines


Part of the solution here is recognizing that spaces for official discussion are _different_ from community hangout spaces. Our code of conduct attempts to handle abrasive behavior, which can disrupt discussions anywhere, but the comments that can disrupt consensus building in official discussions aren't really covered. Nor are the repercussions of code of conduct violations really _appropriate_ for such disruptive comments anyway.

A proposal I've circulated in the past is to have a notion of participation guidelines. Discussions in team spaces (RFCs, pre-RFCs, discord/zulip/IRC channels during team meetings) follow a set of rules set forth by the individual teams. It might be worth having a base set of participation guidelines defined by the core team. Something like the following is a very rough strawman:

 - Don't have irrelevant discussions during team meetings on Discord/IRC/Zulip
 - Don't take threads off topic
 - Don't rehash discussions

We ask people to read these before participating, but also breaking these rules isn't considered serious, it just triggers a conversation (and maybe the hiding/deletion of a comment). If someone repeatedly breaks these rules they may be asked to not participate in a given thread anymore. The primary goal here is to empower team members to better deal with disruptive comments by giving them a formalized framework. Having codified rules helps team members confidently deal with such situations without having to worry as much about drawing direct ire from affected community members.

A base participation guidelines document can also be a value statement, not just a set of rules but also set of values. These values can be things like:

 - "We explicitly value high empathy interactions"
 - "How everyone is feeling is everyone's business"

(h/t [Adam] for the articulate wording here)

Having such words written somewhere &mdash; both the high level values we expect people to hold, and the individual behaviors we expect people to exhibit (or not exhibit) &mdash; is really valuable in and of itself, even if not enforced. The value of such documents is not that everyone reads them before participating &mdash; most don't &mdash; but they serve as a good starting point for people interested in learning how to best conduct themselves, as well as an easy place to point people to where they're having trouble doing so.

On its own, I find that this is a powerful framework but may not achieve the goal of improving the situation. I recently realized that this actually couples really well with a _different_ idea I've been talking about for quite a while now, the idea of having facilitators:

 [Adam]: http://twitter.com/adam_n_p/

## Facilitators

A common conflict I see occurring is that in many cases it's a team's job to think about and opine on a technical decision, but it's also the team's job to shepherd the discussion for that decision. This often works out great, but it also leads to people just feeling unheard. It kinda hurts when someone who has just strongly disagreed with you goes on to summarize the state of the discussion in a way that you feel you've been unfairly represented. The natural response to that for most people isn't to work with that person and try to be properly represented, it's to just get angry, leading to less empathy over time.

By design, Rust team members are _partisan_. The teams exist to build well-informed, carefully crafted opinions, and present them to the community. They also exist to make final decisions based on the results of a consensusbuilding discussion, which can involve picking sides. This is fine, there is always going to be some degree of partisanship amongst decisionmakers, or decisions would not get made.

Having team members also facilitate discussions is somewhat at odds with all of this. Furthermore, I feel like they don't have enough bandwidth to do this well anyway. Some teams do have a concept of "sheriffs", but this is more of an onramp to full team membership and the role of a sheriff is largely the same as the role of a team member, just without a binding vote.


I feel like it would be useful to have a group of (per-team?) _facilitators_ to help with this. Facilitators are people who are interested in seeing progress happening, and largely don't have _much_ of an opinion on a given discussion, or are able to set aside this opinion in the interest of moving a discussion forward. They operate largely at the meta level of the discussion. Actions they may take are:

 - Summarizing the discussion every now and then
 - Calling out one sided discussions
 - Encouraging one-on-one tangents to be discussed elsewhere (perhaps creating a space for them, like an issue)
 - Calling out specific people to do a thing that helps move the discussion forward. For example, something like "hey @Manishearth, I noticed you've been vocal in [arguing that Rust should switch to whitespace-sensitive syntax][lol], could you summarize all the arguments made by people on your side?" would help.
 - Reinforcing positive behavior
 - Occasionally pinging participants privately to help them improve their comments
 - Attempting to identify the root cause of a disagreement, or empowering people to work together to identify this. This one is important but tricky. I've often enjoyed doing it &mdash; noticing the core axiomatic disagreement at play and spelling it out is a great feeling. But I've also found that it's incredibly hard to do when you're emotionally involved, and I've often needed a nudge from someone else to get there.

At a high level, the job of the facilitators is to:

 - help foster empathy between participants
 - help linearize complex discussions
 - nudge towards cooperative behavior, away from adversarial behavior. Get people playing not to win, but to win-win.


It's important to note that facilitators don't make decisions &mdash; the team does. In fact, they almost completely avoid making technical points, they instead keep their comments largely at the meta level, perhaps occasionally making factual corrections.

The teams _could_ do most of this themselves[^5], but as I've mentioned before it's harder for others to not perceive all of your actions as partisan when some of them are. Furthermore, it can come off as patronizing at times.

This is also something the moderation team could do, however it's _much_ harder to scale the moderation team this way. Given that the moderation team deals with harassment and stuff like that, we need to be careful about how we build it up. On the other hand facilitating discussions is largely a public task, and the stakes aren't as high: screwups can get noticed, and they don't cause much harm. As a fundamentally _proactive_ moderation effort, most actions taken will be to nudge things in a positive direction; getting this wrong usually just means that the status quo is maintained, not that harm is caused. Also, from talking to people it seems that while very few people want to be involved in moderating Rust, this notion of _facilitating_ sounds much more fun and rewarding (I'd love to hear from people who would like to help).


And to me, this pairs really well with the idea of participation guidelines: teams can write down how they want discussions to take place on their venues, and facilitators can help ensure this works out. It's good to look at the participation guidelines less as a set of rules and more as an aspiration for how we conduct ourselves, with the facilitators as a means to achieving that goal.


There are a lot of specifics we can twiddle with this proposal. For example, we can have a per-team group of appointed facilitators (with no overlap with the team), and for a given discussion one facilitator is picked (if they don't have time or feel like they have strong opinions, try someone else). But there's also no strong need for there to be such a group, facilitators can be picked as a discussion is starting, too. I don't expect _most_ discussions to need facilitators, so this is mostly reserved for discussions we expect will get heated, or discussions that have started to get heated. I'm not really going to spend time analysing these specifics; I have opinions but I'd rather have us figure out if we want to do something like this and how before getting into the weeds.

 [lol]: https://github.com/mystor/slag
 [^5]: In particular, I feel like Aaron has done an _excellent_ and consistent job of facilitating discussions this way in many cases.

## Prospective outcomes

The real goal here is to bootstrap better empathy within the community. In an ideal world we don't need facilitators, instead everyone is able to facilitate well. The explicitly non-partisan nature of facilitators is _useful_, but if everyone was able to operate in this manner it would largely be unnecessary. But as with any organization, being able to horizontally scale specific skills is really tricky without specialization.

I suspect that in the process of building up such a team of facilitators, we will also end up building a set of resources that can help others learn to act the same way, and eventually overall improve how empathetic our community is.

The concept of facilitators directly addresses the moderation problem, but it also handles the scaling problem pretty well! Facilitators are key in re-linearizing the n-to-n discussions, bringing the "parallel universes" together again. This should overall help people (especially team members) who are feeling overwhelmed by all the things that are going on. 

This also helps with concerns people have that they're not getting heard, as facilitators are basically posed as allies on all sides of the argument; people whose primary goal is to _help communication happen_.

--------


Overall what I've proposed here isn't a fully-formed idea; but it's the seed of one. There are a lot of interesting bits to discuss and build upon. I'm hoping through this post we might push forward some of the discussions about governance &mdash; both by providing a strawman idea, as well as by providing a perspective on the problem that I hope is useful.


I'm really interested to hear what people think!

_Thanks to [Aaron], [Ashley], [Adam], [Ember], [Arshia], [Michael], [Sunjay], [Nick] and other people I've probably forgotten for having been part of these discussions with me over the last few years, helping me refine my thoughts_

 [Ashley]: https://twitter.com/ag_dubs
 [Ember]: https://twitter.com/ember_arlynx
 [Michael]: https://twitter.com/mgattozzi
 [Sunjay]: https://twitter.com/sunjay03
 [Arshia]: http://twitter.com/arshia__
 [Nick]: http://twitter.com/fitzgen/
