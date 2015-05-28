---
layout: post
title: "Github streak: End-game and post-mortem"
date: 2015-05-28 07:48:53 +0530
comments: true
categories: programming
---

More than a [year ago][fifty] I blogged (and [blogged again][fifty-more] later) about my
[ongoing github streak][manishearth].

The GitHub streak has since gone on for more than 500 days[^1], and has been a really enriching experience.

Yesterday; I noticed something. I had reached end-game with this exercise. The streak is something I don't think about anymore,
and I don't make any efforts to keep it going. It just ... happens. My involvement in open source has reached a level where
I don't need to consciously try contributing daily; I have enough interests/responsibilities that the streak is a side effect. This is despite
my current intern being at a place where the code I'm working on is not hosted on GitHub (unlike last year). If the streak breaks, I won't
particularly care; and I _haven't_ been caring for a while now.


... I think that's amazing. Despite me not realizing it at the time, this is the state of affairs that such an exercise would ideally
lead to &mdash; the initial motivation for the exercise replaced with something more substantial, until the excercise is no longer relevant.

I initially started this off after realizing that I had inadvertantly been contributing daily to open source for a week or so. In the past, my
contributions to open source used to be in bursts, which meant that I would be out of touch at times. I decided to try and work on extending this.
After around 30 days, I had a concrete habit. After around 40, I realized that I'd become much more efficient at working on random bugs (even in unfamiliar codebases),
thus being able to spend more time writing real code.

Initially I had set a bunch of rules (listed in my [original post][fifty]), which had stuff like issues/readme edits not counting (and no date manipulation!). I tweaked the rules around the 80-mark
to include issues/readmes when I had written code that day but it was lost in a commit squash or rebase. I think much later I dropped the rules about issues and readme edits entirely;
just considering "anything that shows up on the punchcard which is not a result of date manipulation" to be valid. At that point I was already quite involved in multiple projects
and didn't care so much about the streak or the original rules &mdash; it was just a habit at that point.

Now, I'm a regular contributor to both the [Servo][servo] and [Rust][rust] projects. I also have a bunch of personal projects ([some][clippy] [lints][tenacious] [and][extensible] [syntax extensions][adorn] for Rust, as well as a [gc][gc], along with a lot of older projects that I don't actively work on but maintain) and am trying to regularly blog. I've
also gotten well into the habit of sending pull requests for fixing mistakes or annoyances. When all this comes together, I end up with at least one contribution a day. Sometimes more.
I have tons of things queued that I want to work on (both personal and as a part of Servo/Rust/elsewhere), if only I had the time.

If you do have enough spare time, I do recommend trying this. Once you get enough momentum the power of habit will keep it going, and if
my case is anything of an indicator[^3] you'll eventually have a good chunk of contributions and some concrete open source involvement.

Please note that GitHub streaks shouldn't be used as a metric, _ever_. They're great for self motivation. As a metric for tracking employee performance,
or for filtering interview candidates; not so much. It's way too rough a metric (like LoC written), and oversimplifies the work that goes into code.
As far as using it to boost interview candidates; not everyone has the time or inclination to contribute to open source after a day job in programming,
and _that's okay_. I'm a physics student &mdash; programming is like a hobby for me[^4] which I'll gladly do daily. Now that I have a programming intern,
I'm pretty sure there will be days where I don't want to program further after leaving the office.

[^1]: The punchcard on GitHub only shows 400-something because the streak got retroactively broken by some deletion or rebase &mdash; at that point I didn't care enough to investigate
[^3]: It could equally be just a bunch of luck with meeting the right people and choosing the right projects
[^4]: Though now it's a serious hobby which is a possible career option

[fifty]: http://inpursuitoflaziness.blogspot.in/2014/02/50-shades-of-green.html
[fifty-more]: http://inpursuitoflaziness.blogspot.in/2014/04/50-more-shades-of-green.html
[manishearth]: https://github.com/Manishearth
[servo]: https://github.com/servo/servo
[rust]: https://github.com/rust-lang/rust
[clippy]: https://github.com/Manishearth/rust-clippy
[extensible]: https://github.com/Manishearth/rust-extensible
[tenacious]: https://github.com/Manishearth/rust-tenacious
[adorn]: https://github.com/Manishearth/rust-adorn
[gc]: https://github.com/Manishearth/rust-gc/