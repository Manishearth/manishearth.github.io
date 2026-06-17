---
layout: post
title: "The future of the con is already here, it's just not evenly distributed"
date: 2026-06-01 08:32:30 -0700
comments: true
categories: []
---

# The Set-Up

{% img /images/the-sting/the-set-up.png 500 %}

> Johnny Hooker: Sometime after 2:00, a guy's gonna call on that phone there and give you the name of a horse.
> 

Imagine yourself, perhaps a typically-well-paid, tech-savvy professional, on the job hunt. You've been looking for a while with no luck; the market just sucks right now.

A recruiter reaches out on LinkedIn, and it seems to be a *perfect* opportunity, tailored exactly to your best skills. 

The company is one you've heard about; it's known to be a great place to work. They also pay pretty well compared to your previous job.

Of course you're quite stoked, and agree to some interviews. You have an initial screening call that seems to go well.  They mention that their interviews are under a standard, simple NDA and promise to send it to you over one of those legaltech SaaS startup platforms. You get the email, and after signing in to their enterprise SSO, you see what is, yep, a pretty simple NDA, and sign it.

The interviews go great. The interviewers are warm, welcoming, and you look forward to getting to work with them more. Everything they say about the company sounds amazing.

And then you get the bad news: someone else got the job. Oh well. They did, however, enjoy talking to you and might reach out for future similar opportunities. Anyway, back to the grind.

Six months later, you learn this was all a scam. Your identity has been stolen, and thousands have been spent on credit cards opened in your name. Your brokerage account has been partially drained. It's going to take months to disentangle this, and you're likely not going to get everything back. To top it all off, you have lost access to your email and many other online accounts.

As you are discovering this, you're still bewildered as to how this happened. You never expected this type of thing to happen to *you*; you're well versed with keeping yourself secure on the internet and not prone to common scams.

# The Hook


{% img /images/the-sting/the-hook.png 500 %}

> Henry Gondorff: You can't do it alone, you know. It takes a mob of guys like you and enough money to make them look good.

The point of attack was the login to the NDA signing platform. You chose to use a "sign in with &lt;service&gt;" login when you had to create an account, and it sent you through a realistic-looking login flow: a real Google/iCloud page, perhaps with your email already filled in. When you logged in to this site they used your entered password and subsequent "tap yes on your device" 2FA flow to log in to your account on their end (saving the session cookies), and made it look like a successful login on your end.

The attackers kept this undetected access and monitored your patterns, looking for ways to exploit it. They disabled your smoke detectors before setting off any fires: pre-filtering alert emails from accounts they intended to hit, so warnings never reached you. They downloaded all of your cloud files and used the account to log in to various other sites. They used everything they knew about you to open credit cards in your name. The interview and rejection *after* the compromise were theater — keeping you from getting suspicious so that they could hold on to your credentials longer.

This is pretty scary already, but it gets worse: they managed to drain funds. This is hard: modern financial systems have a lot of protection against hijacked accounts[^banking-protections]. Most scams targeting money involve convincing someone to voluntarily transfer money in an irreversible or untraceable way, and a tech-savvy professional is less likely to be the target of that. 

But it's still possible for a scammer to take money from you with their level of access in a way that lets them keep that money and avoid detection until it's too late. Someone with persistent, undetected access to your email and accounts may notice, for example, that you have paycheck money autotransferring to a brokerage account that you don't seem to touch or log in to often[^dearth]. They might gain access to it by resetting your password, adding a transfer account, and maybe establishing a pattern of usage making small transfers. Eventually, they transfer the funds out, timed so you won't notice for a while, in a way that's hard to trace[^mules]. Maybe they can wait for you to be on vacation, because they know when that is: they have your calendar!

After they're all done and think the scam will be detected soon anyway, they lock you out of your accounts to make it harder for you to piece together what happened.

Yeah ... all of that sounds possible.

It's also a *lot* of effort, needing multiple people coordinating together and monitoring things, for a payoff that might not happen. Feels unlikely, right?

Well, I left out one part. This entire attack was orchestrated and carried out by an LLM.

An LLM which could research everything about you and craft a tailored attack. An LLM that could put together all the things that would be needed to make this seem plausible (a LinkedIn account, a fake document signing website, a plausible-looking domain to send emails from), and synthesize all text, audio and video interactions. An LLM which, after gaining access to your account, could monitor it and find the best ways to make use of that access, whether it be worming its way into your brokerage, racking up huge cloud spends on AWS, taking all your crypto, or even ransoming your decades of precious data from your now-stolen, likely-wiped Google account.

And the job hunt was incidental. The interview was the scam that fit you; a plausible way to hook you in based on what the scammers knew about you. For someone else, it might be a scary call from the police, a relative asking for help, an email from their bank, or a slow-burn romance. The pretext changes each time, but the machinery behind it is the same.

 [money mules]: https://www.fbi.gov/how-we-can-help-you/scams-and-safety/common-frauds-and-scams/money-mules
 [^banking-protections]:  Involuntarily transferring your money would involve initiating a bank transfer via online banking. This would potentially be noticed, transfers take a few days, and the target account could be traced due to KYC regs. Furthermore, banking sites often use 2FA and notify the user when there is a login.
 [^mules]: The tracing of the actual outflow can be thwarted by using (unsuspecting) [money mules], a well-established tactic in the scam world. Admittedly, this adds more days to the process where you might notice something is wrong, but it does appear to be feasible.
 [^dearth]: From the dearth of "login detected to foo.com" emails in your inbox

# The Tale


{% img /images/the-sting/the-tale.png 500 %}

> Henry Gondorff: It's not like playing winos in the street. You can't outrun Lonnegan.

For quite a while now, you could broadly categorize scams into two buckets: cheap, easy-to-run spray-and-pray scams hoping to ensnare the less savvy; and expensive, *targeted* scams, aimed at people worth the trouble. And usually "people worth the trouble" is more about *organizational* power someone holds rather than going after personal savings, like [this $25M scam in Hong Kong][arup] where an employee of a company was convinced to transfer company funds.

Spray-and-pray scams are cheap because they often spend no effort in convincing you. In fact, the "Nigerian Scammer" trope exists because [for scammers running scams against less-savvy individuals, it is highly desirable that the more-savvy individuals self-select out of their pipeline as early as possible][nigerian-why]. Emails are free, but the subsequent work to correspond with and scam a mark is not.

Tech-savvy people are, by and large, not prone to these scams: A handful of computer security best practices, paired with a rough understanding of the system's capabilities[^caller-id] keeps you reasonably secure.

However, with respect to more sophisticated scams, most people aren't "worth the trouble", or at least think they aren't. Most people don't have $25M buttons available to them at work.

Sure, many professionals have enough savings that it would make sense to mount a sophisticated scam, but also the likelihood of it happening to them is still slight: a scam that takes that amount of effort takes a lot of setup time and can't just be scaled up; you need people with the sophistication to run this scam willing to become criminals, and that doesn't parallelize well. There's the old joke: you don't have to outrun the bear, you just have to outrun the guy running next to you. You don't have to be unscammable, just a bigger pain to scam than the next mark.

Note that sophisticated scams against an individual's wealth [do happen][the-cut] [^patrick-shoebox]. "It can't happen to me" isn't quite the right framing, but "it's unlikely this will happen to me" is a common belief, and not unreasonable for many to hold.


Quoting [James Mickens](https://www.usenix.org/system/files/1401_08-12_mickens.pdf):

> <small>Basically, you’re either dealing with Mossad or not-Mossad. If your adversary is not-Mossad, then you’ll probably be fine if you pick a good password and don’t respond to emails from `ChEaPestPAiNPi11s@virus-basket.biz.ru`. If your adversary is the Mossad, YOU’RE GONNA DIE AND THERE’S NOTHING THAT YOU CAN DO ABOUT IT. The Mossad is not intimidated by the fact that you employ `https://`. If the Mossad wants your data, they’re going to use a drone to replace your cellphone with a piece of uranium that’s shaped like a cellphone, and when you die of tumors filled with tumors, they’re going to hold a press conference and say “It wasn’t us” as they wear t-shirts that say “IT WAS DEFINITELY US,” and then they’re going to buy all of your stuff at your estate sale so that they can directly look at the photos of your vacation instead of reading your insipid emails about them.</small>


Mickens is talking about state actors which are a whole other level. But the core idea is the same: adversary capability is bimodal, clustered at "untargeted × cheap" and "targeted × expensive". And running targeted attacks *at scale* just doesn't work.

Correction, adversary capability *was* bimodal. LLMs fill the middle of the distribution. They're pretty cheap: [A 2024 paper][heiding] found that LLMs tasked with spearphishing cost around 4¢ per email. The interview scam laid out above is more involved and more expensive, but likely still worth it, and 2026 LLMs are leaps and bounds better.

Chillingly, _this scales_: one can be running thousands of these scams at once! A scammer could probably even have LLMs research individuals and serve them up with bespoke scams designed for that individual's dossier.

We are now in a world where scams can be run in a `for` loop.


 [nigerian-why]: https://web.archive.org/web/20120622161722/http://research.microsoft.com/pubs/167719/WhyFromNigeria.pdf
 [arup]: https://www.cnn.com/2024/02/04/asia/deepfake-cfo-scam-hong-kong-intl-hnk/index.html
 [the-cut]: https://www.thecut.com/article/amazon-scam-call-ftc-arrest-warrants.html
 [heiding]: https://arxiv.org/abs/2412.00586
 [^caller-id]: Remember, phone numbers in Caller ID and `from:` headers in emails can be spoofed!
 [^patrick-shoebox]: Also worth reading Patrick McKenzie's [excellent followup investigative journalism](https://www.bitsaboutmoney.com/archive/two-americas-one-bank-branch/) on that article.


# The Wire


{% img /images/the-sting/the-wire.png 500 %}

> Eddie Niles: The wire's been out of date for ten years.
>
> Henry Gondorff: That's why he won't know it.

Here's a partial list of scam-relevant capabilities that LLMs have that would previously require significant skilled human effort per target:
 
 - Researching a mark to find out the best way to go after them.
 - Personally tailoring all communication with a mark in mind, dynamically adjusting based on how they respond to various approaches.
 - Cloning the voice of a person the mark trusts, like a relative.
 - Plausible, real-time deepfaking of a video call.
 - Building a plausible-looking corroborating fake web presence [^fn-lorenzo]
 - Realtime monitoring of compromised resources, and dynamically building up the scam based on this monitoring.
 - Better triage and discovery of marks.
 - Avoiding signature-detection based spam filters (shown by [Heiding et al][heiding]).
 - Scanning for and chaining known exploits in unpatched deployed software. Mass scanning isn't new, but cheaply building tooling that can keep tabs on the latest [CVE]s and learn new tricks is[^zerodays].
 
These are capabilities that exist *today*, and they'll only improve from here. We should look at these skills as a floor, not a ceiling.

Each of these is dangerous on its own, but they're also *cheap*. A con with a cost measured in tokens can be run many times over -- "scams in a `for` loop" -- and scaling unlocks some moves that aren't available in an individual scam.

First off, scaling unlocks _patience_. A scammer team going after an individual may not have the capacity to wait months or years between steps of the process, which limits the types of things they may try. However, a scammer using LLMs to go after many people at once can totally afford to have an operation go dormant for a while, waiting for the right moment to pounce. They can even use the time to layer multiple scams performed significantly far apart.

Secondly, scaling unlocks _composition_. Scams can be compounded across fronts to defeat scam-protection mechanisms: For example, one can run a small, less sophisticated scam to recruit a money mule that enables them to extract a large quantity of funds in an untraceable way.

(I really like the classic 1973 movie [The Sting][sting]. One aspect of the con central to the movie is that the crew uses multiple smaller confidence tricks to suborn/spoof various "trusted" institutions, giving them, for example, the ability to credibly pretend to be working for a major bank. But now, in this current era, what took Henry Gondorff an old pool hall, betting equipment, disguises, a cast of 50 people, and a whole host of other things ... that now takes a handful of tokens to achieve.)

Scaling unlocks one last thing: it unlocks _new targets_. These are still ultimately scams against people, but a thousand compromised marks is also a thousand authenticated positions[^suborn] inside the platforms they use, and that's a very different kind of asset. Plenty of systems have apparent seams where attempts to exploit them will *eventually* be caught and reversed[^glitch]. ["The optimal amount of fraud is nonzero"][fraud]: these seams usually have benefits that outweigh the costs of the occasional fraudster. A thousand accounts working in concert to simultaneously exploit one of these seams, however, changes that calculation entirely. A seam a platform has made a calculated choice to live with is now a gaping hole it needs to scramble to close[^viral].

Putting this together still requires skill[^skill] ... for now. Eventually someone will build reusable tooling for this and sell it to other scammers, giving rise to "[script kiddies][skiddie] but for scams". There are well-established [marketplaces for scammers][genesis], someone just needs to build this tooling and sell it there. This may even have already happened.

["The future is here, it's just not evenly distributed"][future]: the capabilities are there, and some scammers are almost certainly deploying them already. But since they're not yet *ubiquitous*, our heuristics — and those of companies providing us with critical services — have not yet been recalibrated.


 [lorenzo]: https://www.youtube.com/watch?v=0MC55lU_L2E
 [skiddie]: https://en.wikipedia.org/wiki/Script_kiddie
 [genesis]: https://en.wikipedia.org/wiki/Genesis_Market
 [future]: https://www.goodreads.com/quotes/681-the-future-is-already-here-it-s-just-not-evenly
 [sting]: https://en.wikipedia.org/wiki/The_Sting
 [^skill]: While I know enough to identify some of these capabilities, I'm not good enough at LLMs to deploy them effectively myself without needing to spend time testing and building tooling.
 [^suborn]: Note that credential/identity theft is not the only way to get an authenticated position; a scammer may simply *convince* a more-credulous mark to carry out the steps they suggest.
 [^glitch]: If you think you found a cool new free money glitch, no you didn't, [that's fraud][xkcd-fraud].
 [^viral]: Large-scale coordinated exploits of seams in the system already happen when coordinated by human behaviors rather than LLMs: in 2024 a check-fraud "[free money glitch][chase-glitch]" went viral on TikTok, and enough people fell for it that Chase ended up filing [a couple lawsuits][chase-lawsuit]. But a scammer with access to your accounts doesn't need to engineer a viral trend first.
 [chase-glitch]: https://www.cnn.com/2024/09/03/business/chase-tiktok-trend/index.html
 [chase-lawsuit]: https://www.theguardian.com/business/2024/oct/29/jpmorgan-sues-customers-glitch-tiktok-bank-atm-checks
 [xkcd-fraud]: https://xkcd.com/1494/
 [^fn-lorenzo]: Or as Barney Stinson calls it, the [Lorenzo Von Matterhorn][lorenzo]
 [^zerodays]: Frontier models are also [getting terrifyingly good](https://www.anthropic.com/news/mozilla-firefox-security) at finding *novel* software vulnerabilities, something that has historically been extremely expensive. But this slots into a different dynamic: zero-days are typically perishable precision weapons to spend on a high-value target, not something to run in a `for` loop against a database of marks. There's a parallel arms race going on here and it's worth knowing about, but it's not the primary concern of this post.
 [CVE]: https://www.cve.org/

# The Shut-Out


{% img /images/the-sting/the-shut-out.png 500 %}

> Johnny Hooker: He's not as tough as he thinks.
>
> Henry Gondorff: Neither are we.


Speaking of heuristics, if you were asked how you'd fare against some particular scam, you'd probably have answers ready. If a family member texts you about something, you'd call or, better, video chat with them to verify. If someone contacts you out of the blue, you look them up. You are on the lookout for inflection points in a conversation with someone you don't know, to see where it switches from idle discussion to something impactful. These are great instincts, the instincts of someone who has been paying attention in this internet age.

But why did these heuristics work?

Some of these heuristics are proxies for cost. Fluent, personalized writing means a real person, and a scammer working thousands of marks may not have the time to spend on that. A strong web presence can be faked, but that takes a ton of work. You didn't think a scammer would be likely to spend that much effort solely on *you*, and that informed your adoption of these heuristics.

Other heuristics are measures of capability. A scammer wouldn't previously be able to impersonate a family member on a phone call. If you met a person on a video call, they would be real, and likely identifiable to the police if it came to that.

Both of these foundations are crumbling, and this means our heuristics are breaking.

It gets worse: we didn't just need these heuristics to protect ourselves from scams, we needed them to be certain anything is real. Now we're often left not-totally sure, suffering from the [liar's dividend][liar]. What do you do when a family member in a different city appears to need emergency money, but could also plausibly have had their accounts compromised with all communications being intercepted and deepfaked? Fly out to check on them in person? Perhaps ask someone else in their city to check in on them? This is far more effort than before.

Furthermore, personal heuristics are only a part of the story: institutions have heuristics too. American consumer banking protections[^regulations] draw a strong red line based on who authorized a transfer: if someone gained access to your account and did a fraudulent transfer, you'll be made whole by the bank. On the other hand, if you've been convinced to move money, even for illegitimate reasons, you may be able to report a crime but nobody is under any obligation to make you whole. This might make sense in a world where "stolen password" is easier than a targeted, manual "send us money" con, but that's changing[^fraud-cost].

 [liar]: https://en.wikipedia.org/wiki/Liar%27s_dividend
 [^regulations]: See [Regulation E][rege]. Different countries have different regimes, the UK [recently passed a law](https://www.gov.uk/government/news/new-powers-for-banks-to-combat-fraudsters) that requires banks to make whole customers who were tricked into transferring money. It's unclear to me if this is in response to LLMs, but it's from 2024 and I do not have a great impression of the UK legislature's understanding of tech, so probably not.
 [rege]: https://www.bitsaboutmoney.com/archive/regulation-e/
 [^fraud-cost]: This isn't to say that Reg E-style "the bank is required to make whole anyone who gets scammed" is the right call here either: too many costs moved onto the banks and they may start choosing to not do business with people who are likely to get scammed. Someone who understands this field more than I could probably suggest workable, concrete, steps that institutions (both banks and regulators) might be smart in taking.


# The Sting


{% img /images/the-sting/the-sting.png 500 %}

> Johnny Hooker: Then why are you doing it?
>
> Henry Gondorff: It seems worthwhile, doesn't it?

So what do we do? It's tempting to crank every heuristic to eleven: scrutinize each email, each voice on the phone. But this won't work; these heuristics were a proxy for detecting something that is now cheap to fake.

I remember when I grew up we were forbidden from using Wikipedia for researching school projects (and occasionally told that Wikipedia was not useful for *any* purpose). Teachers believed that because Wikipedia could be easily edited, it could contain incorrect information, and we shouldn't rely on that. People had heuristics for truth that incorporated "published material is probably true to some degree of certainty", based on the reality that printing incorrect information for a jape is hardly cheap. "Don't include Wikipedia in this category and ignore it entirely" is one way to preserve that heuristic, and is what they wanted us to do. This was a correction in the wrong direction. The world was changing so that this heuristic was faltering; we needed to build new heuristics to handle the new world, not cling desperately onto pretending the world hadn't changed. 

Kids are *famously* good at following rules they disagree with. So my generation still used Wikipedia, and in a broader sense grew up alongside the explosion of information on the Internet. We got pretty okay at building new heuristics: learning to check sources, looking for corroborating evidence, stuff like that. The people who stuck to the old heuristics (often of older generations) have been much more easily targeted by e.g. modern misinformation campaigns.


So, we should improve our heuristics again. There are a couple ways to do that[^not-an-expert]:

One heuristic we can build is detecting the common skeleton of scams. Many scams follow a skeleton where they'll ask for something urgent, in secret, asking you to use unusual channels. This skeleton is usually noticeable because the pitch around it is often clumsy[^ceo-starbucks], but that can change with scammers who can do triage and research marks at scale. Still, the rough structure of that skeleton probably isn't going anywhere; an ask is an ask.

Other heuristics can be achieved by verifying things through more channels. For further verification, I *strongly* recommend setting up some spoken passwords with your family members. In cases where you don't have that, you can try to still call back to events in the past that are unlikely to have records out there. For less tech-savvy family members I would recommend just giving them the advice "if you get a call from me talking about something serious, urgent, and/or secret, be very skeptical and maybe hang up and check through another channel".

Somewhat recently I was setting up a financial transaction with a person I know. We had been talking about it over multiple platforms, but before the final step I ended up asking them to hop on a video call, explaining that I was being extra cautious in the age of LLMs. They replied, in effect, "heh, I wondered when I was going to start getting asked this". They opened the video call referencing a specific memorable moment in a call we had many years ago, and we ended up chatting for a while about various things including the subject of this blog post.

It helps to understand where our systems do and don't protect us. A rough rule: you can't usually trust the authenticity of communication you *receive*, but you can mostly trust where you deliberately *send* something[^access]. An email composed to some address will likely[^smtp] reach that inbox, and a call you place to a number will likely[^ss7] reach that device. Email `from:` headers and caller ID, on the other hand, can be easily forged.

These heuristics are imperfect, but they're better than what we have now, and will make you more expensive and trickier to target. It's not practical to be 100% completely unscammable ("[the optimal amount of fraud is nonzero][fraud]"), but you can at least be more expensive to scam.

Beyond improving heuristics, following security best practices like using [hardware 2FA][2fa-instructions] [^fido] (rather than SMS or an authenticator app) can protect you against many tools in the scammer toolbox.


The next few years are going to be really interesting in a lot of different ways. I'm *expecting* that institutions and systems will themselves eventually adapt to many of these things[^redteam] and come up with better protections[^android]. That's going to take time, though, and potentially be a bit of an arms race. In the meantime I expect scams to skyrocket. All of the capabilities described in this post exist and could be put together in many creative ways. Think about what that means for yourself, your friends, and your family, and see what you can do to help them.

The future of the con is already here. It's just not evenly distributed yet.


_Thanks to [Patrick McKenzie](www.bitsaboutmoney.com), [talia](https://taliatales.substack.com), [Inanna Malick](https://recursion.wtf), Alice Fares, Tilia Bell, [jyn](https://jyn.dev/) and [Jane Lusby](https://github.com/yaahc) for providing feedback on drafts of this blog post._

_While researching parts of this post, I stumbled upon [a post with a similar thesis from a year ago][zellyn], which even uses the same Mickens quote. It's a good read as well._


 [zellyn]: https://zellyn.com/2025/03/ai_security_nightmare/
 [fraud]: https://www.bitsaboutmoney.com/archive/optimal-amount-of-fraud/
 [^ceo-starbucks]: Hi, I am your CEO, I need $1000 in starbucks gift cards urgently for a client meeting. It needs to be gift cards because uhhhh ....
 [^access]: Whether or not someone unauthorized has access to an email inbox or phone is a different question; this is about whether they can pretend to be that email/phone without having gained access.
 [^smtp]: Though this depends on the actual mail servers in use. It is almost completely not a problem in the modern era.
 [^ss7]: Less likely than email: see "SS7 attacks". Stingrays are also a tool used by law enforcement, though that requires a physical presence, and state-level actors have a lot more tools at their disposal here in general anyway.
 [^not-an-expert]: I'm not an expert at this. I like reading about fraud and scams, and I like thinking about security, but I recommend listening to others who are better experts in these fields.
 [^fido]: FIDO2/WebAuthn, *where offered*, include the website's domain in the cryptographic exchange, so a phishing website cannot simply pass the signature through.
 [^android]: Just recently, Android introduced [impersonated call detection][android-call].
 [android-call]: https://blog.google/security/android-fake-call-detection/
 [^redteam]: Defenders get these capabilities too! Mozilla's [conclusion from using Mythos to red-team Firefox][mozilla-bholley] was optimistic: they believe there's a real chance that by running these tools they can actually find *all* of the security vulnerabilities, instead of playing best-effort whack-a-mole.
 [mozilla-bholley]: https://blog.mozilla.org/en/privacy-security/ai-security-zero-day-vulnerabilities/
 [2fa-instructions]: https://www.makeuseof.com/i-set-up-hardware-based-2fa-simpler-than-i-thought/