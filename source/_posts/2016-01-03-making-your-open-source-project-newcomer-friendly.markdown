---
layout: post
title: "Making your open source project newcomer-friendly"
date: 2016-01-03 18:56:24 -0800
comments: true
categories: programming
---

One reason I really like open source is that it offers a lot of great opportunities for newish programmers to get some hands-on experience with real world problems. There's only so much one can learn from small personal projects; but in open source one often gets to tackle interesting problems on large codebases &mdash; problems which wouldn't occur in small/personal ones. There are also valuable skills related to collaboration to be learnt.

Because of this, I care quite a bit about making projects welcoming to new contributions, and try to improve this experience on projects I'm involved in. I've picked up a few tricks along the way. Most of these aren't my ideas, I've gleaned them from watching people like [Josh Matthews][jdm], [Margaret Leibovic][leibovic], [Mike Conley][mconley], and [Joel Maher][jmaher] do their thing. If you're interested, [here][leibovic-post] is a post by Margaret, and [here][jdm-slides] are some of Josh's slides from a presentation, both on the same subject.

 [jdm]: https://twitter.com/lastontheboat
 [leibovic]: https://twitter.com/mleibovic
 [mconley]: https://twitter.com/mike_conley
 [jmaher]: https://twitter.com/redheadedcuban
 [leibovic-post]: http://blog.margaretleibovic.com/2013/08/06/increasing-volunteer-participation-on-the-firefox.html
 [jdm-slides]: http://www.joshmatthews.net/fsoss15/contribution.html

Before I get started, bear in mind that making a project "newbie-friendly" isn't something that magically happens. Like most things, it takes effort, but often this effort can come to fruition in the form of motivated contributors helping out on your project and eventually even becoming co-maintainers. It's really worth it!

## The simple stuff

There's a lot of really easy stuff you can do to kickstart contributions to your own project. Most of this is obvious:

### CONTRIBUTING.md

**Add a `CONTRIBUTING.md`** file. Keep it up to date. Link to it prominently from the README. The README should also have clear and detailed instructions for building the project. These two files are different -- README is for those who want to use your project (perhaps by building from sources), CONTRIBUTING is for people who want to contribute.

**Mention steps for getting involved**: how to find something to work on, how to send a patch/make a pull request, a checklist of things to ensure your patch/PR satisfies before submission (e.g. passing tests, commit message guidelines, etc).
Additionally, include some tips and tricks (like a link to the internal documentation) that can help new contributors, links to communication channels (IRC, Slack, Gitter, whatever) and anything else you may find helpful for someone considering contributing to your project. If you use some form of issue labeling, explanations of the labeling scheme can help folks find stuff they want to work on. An overview of the directory structure can be similarly helpful.

For some examples, check out the CONTRIBUTING.md files for [servo][servo-contri] and [rust-clippy][clippy-contri].

### Maintain a list of easy bugs

More on this later, but try to **use some form of tagging to mark easy bugs**. I love [this slide][fuckoff] from Josh's talk.

> How to politely say f\*\*\* off
>
> "Choose something to work on from our issue tracker." <br>
> &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; - every project maintainer

Most bugs on issue trackers are nontrivial, steeped with jargon, devoid of actionable information, or otherwise inaccessible to the average new contributor. It's relatively low effort to recognize bugs which are "easy" for maintainers, but it's a lot of work for people unfamiliar to this project to figure this out.

A simple label on GitHub is all you need in most cases. Be sure to link to it from your contributing file!

### Communicate!

**Have open channels** for communication. IRC is often the favorite here, though IRC is pretty alien for people getting involved in open source for the first time. If you're using IRC, see if you can link to a web client (like [Mibbit][mibbit]) with short instructions on how to join. Stuff like Gitter works too.

Mailing lists also work &mdash; everyone knows how to email! However, email can be intimidating to newcomers; many have a "omg I can't ask my silly questions here!" attitude which stops them from progressing.

Explicitly inviting questions in each issue helps here. Clippy doesn't have a mailing list or IRC channel (too small a project), but I encourage people working on new bugs to ping me on any communication channel they'd like. I've mentored people over email, GH issue threads, IRC, even reddit PMs, and it's worked out fine in each case.

Often folks will PM you for help. Provide help, but **encourage them to ask questions** in the main venue. This has the twofold benefit of showing everyone that the main channel is open to questions, and it also helps people get quicker answers since someone else can answer if you're not around.

 [mibbit]: https://wiki.mibbit.com/index.php/Widget

### Recognition

**Celebrate new contributors**. Tweet about them. Mention them in blog posts. Getting a two-line patch accepted in an open source project doesn't sound like much, but when you're just getting started, it's a very awesome feeling. Make it more awesome! Both [This Week In Rust][twir] and [This Week In Servo][twis] mention new contributors (sometimes we tweet about it too), and I've often got very happy messages from these contributors about the mentions.

### Add a code of conduct

A lot of folks have had bad experiences with people online, often in other open source communities and may be wary about joining others. **A code of conduct** is a statement that unsavory behavior won't be tolerated, which helps make the project more welcoming and appealing to these people, simultaneously making it a nicer place which is helpful for everyone. Of course, you should be prepared to enforce the code of conduct if the situation requires it.

I use the [Rust code of conduct][rcoc] but the [Contributor Covenant][covenant] is good, too. Various language/framework communities often have their own favorite code of conduct. Pick one.


 [clippy-contri]: https://github.com/Manishearth/rust-clippy/blob/master/CONTRIBUTING.md
 [servo-contri]: https://github.com/servo/servo/blob/master/CONTRIBUTING.md
 [fuckoff]: http://www.joshmatthews.net/fsoss15/contribution.html?full#issuetracker
 [rcoc]: https://www.rust-lang.org/conduct.html
 [covenant]: http://contributor-covenant.org/
 [twis]: https://blog.servo.org/
 [twir]: http://this-week-in-rust.org/

### Empathize!

We often forget how hard it is to jumpstart in something we're an active part of. For example, for many of us the process of making a pull request is almost second nature.

However, not everyone is used to these things. I've seen contributors who can code well but haven't used Github in the past having lots of trouble making and updating a pull request. The same applies to other workflow things; like code review, version control[^4], or build system peculiarities. 

Keep this in mind when dealing with new contributors. These are skills which can be picked up relatively quickly, but those without them will have a frustrating experience and end up asking you a lot of questions.


 [^4]: I've lost track of the number of times I've helped someone through `git rebase` and merge conflicts on Servo

## Improving the newcomer experience

Alright, now you've gotten all the basics done. People now have a vague idea of how to contribute to your project. Let's make it more concrete.

### Mentoring

Don't just leave an easy bug open. **Offer to mentor it!** This is a very fun and rewarding experience, and of course contributors are more likely to stick around in a project they percieve to be helpful and welcoming.

It's often better to go one step further and **give tips for fixing the issue before anyone even picks it up** ([example][mentor-tip]). Communication in open source has latency &mdash; the contributor might be on the other side of the planet, or might otherwise be contributing at a different time of the day than you[^1]. Reducing the number of back-and-forth cycles is really helpful here, and giving some info so that a contributor can get started immediately without needing to wait for a response goes a long way in improving the newcomer experience.

Avoid creating a mentored bug where you yourself aren't certain on how to fix it. Ideally, **you should know the exact steps to take to fix a bug** before marking it as mentored. Don't divulge all the steps to the mentee, but the exercise of solving the bug yourself (without writing the code) ensures that there aren't any hidden traps.

Mostly mentorship just involves **answering questions and laying out a path** for the mentee. Be sure to encourage questions in the first place! A lot of people, especially students, are intimidated when joining open source and try to stay as quiet as possible. For a healthy mentorship, you want them to ask questions. A lot. Encourage this.

Remember that in many cases the new contributor may be intimidated by _you_. For example, I've often come across new Firefox contributors (who I introduced to the project) asking me questions instead of their assigned mentor because "the mentor works for Mozilla and is way too awesome for me to bug with questions". This wasn't something the mentor told them (Firefox mentors are all very nice and helpful people), it was a conclusion they came to on their own &mdash; one which would impede their progress on the bug.

One trick that helps mitigate this is encouraging questions in your main channel. When people PM me with questions on IRC, I answer their questions, but also encourage them to ask in the main IRC channel next time. This is good for everyone &mdash; It gives the channel an aura of being "okay to ask questions in" (if other people see that questions are being asked and answered in the channel), and it also lets other maintainers jump in to help the new contributor in case I'm not around.

Once a new contributor has fixed a bug, mentorship isn't over -- it's just started! See if you can find something more involved for them to work in a related area of the codebase. Get to know the contributor too, a sense of familiarity goes a long way in reducing intimidation and other friction.

 [mentor-tip]: https://github.com/rust-lang/rust/issues/10969#issuecomment-158282317

 [^1]: This often happens with open source projects with paid staff -- the staff is around during the workday, but the contributors are around during the evenings, so there's less overlap.

### Tailoring process for newcomers

Most open source projects have a set of hoops you have to jump through for a pull request to be accepted. These are necessary for the health of the project and pretty straightforward for existing contributors, but can be intimidating for new ones. They also add extra cycles of communication. I've often seen people put up almost-working patches, and disappear after a few cycles &mdash; even though the bulk of the work was done and there were just process issues (or code nits) left over for merging; which can be quite disheartening. Reducing extra process helps mitigate this.

For example, Servo uses this great tool called [Reviewable][reviewable] for code review. Regular contributors don't have much friction whilst using this, so we use it wherever possible. However, for small pull requests from new contributors I avoid using Reviewable and instead opt to review directly from the GitHub interface. For these pull requests I don't need Reviewable's features, so I don't lose much, but now the contributor has to go through one less hoop.

Similarly, for rust-clippy, I often make minor fixes and run [the readme update script][clippy-readme] on behalf of the contributor instead of asking them to do it themselves. I usually check out the PR locally, run `git merge pr-branch --no-commit --no-ff`[^3], make edits, commit and push. This way the PR still gets marked as merged (`commit --amend` doesn't do that), and the history stays bisectable.

OpenSSL uses a mailing list for patches, however they allow contributions via GitHub too. Most seasoned contributors probably stick to the mailing list, but new contributors can use the familiar GitHub interface if they want, reducing friction.

Of course, cutting down on (necessary) process should only be done for the first one or two contributions; try to educate the newcomer about your processes as time passes.

An alternate way to tackle this issue is to go the other way around and teach process first. Give newcomers an extremely easy bug that just involves replacing a string or some other simple one-line fix, and help them push it through the process. This way, the next time they work on something, they'll be familiar with the process and be able to devote more time to the actual code.


 [reviewable]: http://reviewable.io/
 [clippy-readme]: https://github.com/Manishearth/rust-clippy/blob/master/util/update_lints.py

 [^3]: There are various reasons why you should _not_ do this, mainly because non-merge-related changes in merge commits are hard to track down. Be aware of the downsides and use this trick judiciously.

### Creating easy bugs

At some point down this road many projects have a problem where there are people who want to contribute, but not enough suitable easy bugs.

One technique that has helped me create a lot of easy bugs is to just **look out for separable and non-critical subfeatures when working on something**. There often are things like polish or other small features which you don't need to include in the main pull request, but you do anyway because it's a few extra seconds of work. If you think it can be split out as an easy bug, go ahead and file it!

For example, whilst working on some [form issues][servo-manish-form], instead of completely implementing something, I implemented just what I needed, and [filed an easy bug][servo-form-issue]. [This][servo-submit-issue] is another bug with a very similar situation; I'd implemented the framework for form submission, made it work with `<input>`, and filed an easy bug for wiring it up to `<button>`.

Sometimes you may not find a subfeature that can be split out, but you may notice something else which could be improved. [This][servo-fromstr-issue] is an example of such an issue. I was working on something else, and noticed that this area of the code could be designed better. Whilst I could have fixed it myself with very little effort as part of my other changes, I made it into an easy bug instead.

**Simple refactorings** can be a source of easy bugs too. These require familiarity with the language, but not much more, so they're ideal for people new to the project.

It's also possible to take a hard bug and make it easier, either by partially implementing it, or giving enough hints (code links, explanations, etc) that the hard part is already taken care of.

**Avoid making "critical" (i.e, needs to land in a week or two) features into easy bugs**. Even simple changes can take a while for new contributors (especially due to the nature of asynchronous communication, lack of time, and/or getting bogged down in the process). Easy bugs should be something which you _eventually_ want, but are okay with it taking longer to solve. It's very disheartening for a new contributor if they are working on something and a maintainer solves it for them because it was needed to land quickly. (Given enough time this will eventually happen for some bug, in such a case see if you can provide a different bug for them to work on and apologize)


 [servo-manish-form]: https://github.com/servo/servo/commit/b677f0f4ae718c9c6953134bbed27656a6aeb48d
 [servo-form-issue]: https://github.com/servo/servo/issues/7726
 [servo-submit-issue]: https://github.com/servo/servo/issues/4534
 [servo-fromstr-issue]: https://github.com/servo/servo/issues/7517

### Discoverability

Make it super easy for newcomers to **find a bug they _want_ to work on**; not just any easy bug!

[Bugs Ahoy][bugsahoy] and [What Can I do for Mozilla][asknot] are both great examples of this. Servo has [servo-starters][servo-starters].

There are also various sites where you can list your easy bugs, some of which are listed in [Emily's post][edunham-openhatch].

 [bugsahoy]: http://www.joshmatthews.net/bugsahoy/
 [asknot]: http://whatcanidoformozilla.org/
 [servo-starters]: http://servo.github.io/servo-starters/
 [edunham-openhatch]: http://edunham.net/2015/11/04/beyond_openhatch.html


### Projects and more involved participation

Having easy bugs and mentoring newcomers is just one step. You probably want to have these newcomers working on harder stuff, projects, and perhaps eventually maintianing/reviewing!

For many people these steps may not necessarily require involvement from you; I've seen professional software developers move their way to being a maintainer with very little mentorship just because they're experienced enough to figure out how the project works on their own.

However, many of your contributors may be students or otherwise inexperienced; indeed they may be contributing to your project to _gain_ this experience and become better developers. Such people can become valuable members of the team with some effort.

This mostly involves **nudging people towards harder bugs and/or projects**. It's also very valuable to maintain a list of "student projects" (noncritical but large bodies of work). These can be picked up by contributors or sometimes students wishing to do a project for course credit.

It's important to **try and provide a logical series of issues** instead of picking things randomly around the project so that the contributor can focus on one part of the codebase while starting out. If the issues all culminate in a large feature, even better.

Joel Maher and the Mozilla Tools team [have started a pretty great program called "Quarter of Contribution"][qoc] which provides focused mentorship for a particular project. It seems to work out well. Programs like Google Summer of Code and Outreachy also provide ways for new contributors to try out your project at a significant level of involvement.

_Creating_ such projects or harder bugs is a nontrivial problem, and I don't have a clear idea on how this can be done (aside from using similar techniques as listed in the "creating easy bugs" section above). Ideas welcome!

Projects aren't always necessary here either. Depending on the contributor, sometimes you can present them with a regular (i.e., not "easy" or otherwise earmarked) issue to work on, provide some hints, and tell them to try and figure stuff out without your help (or with less help). Stay involved, and encourage them to ask questions of others or initiate discussions, but try to stick to observing. It's really fun to watch someone figure stuff out on their own. I did this with a contributor [here][waffles-levenshtein], where I only provided the initial hint and the code review; as well as [here][waffles-error], where I encouraged the contributor to initiate and direct the relevant bikeshedding on various channels without my involvement. The contributor is now more in touch with the Rust community and codebase as a result; and for me I enjoyed watching him figure stuff out and direct discussions on his own.

 [qoc]: https://elvis314.wordpress.com/2015/10/02/hacking-on-a-defined-length-contribution-program/
 [waffles-levenshtein]: https://github.com/rust-lang/rust/pull/30377
 [waffles-error]: https://github.com/rust-lang/rust/pull/29989

## Mentor! Share!

I'm still exploring these techniques myself. I've had great results applying some of these to [clippy][clippy], and we already apply many of them to Servo. I'm [slowly working on applying these techniques to Rust][rust-discuss-mentor].

While some of these projects I'm always open to hearing about more ideas for making it easier for newcomers to contribute, so please let me know if you have any ideas or experiences to share!

Mentoring, while a lot of work, is an insanely rewarding experience, and I hope you try to incorporate it into your open source projects!

_Thanks to Josh Matthews, James Graham, Emily Dunham, and Joel Maher for feedback on drafts of this post_

<small>discuss: [HN](https://news.ycombinator.com/item?id=10836345)</small>

 [clippy]: https://github.com/Manishearth/rust-clippy/
 [rust-discuss-mentor]: https://users.rust-lang.org/t/mentoring-newcomers-to-the-rust-ecosystem/3088