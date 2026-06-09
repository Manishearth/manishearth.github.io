---
layout: post
title: "The future of the con is already here, it's just not evenly distributed"
date: 2026-06-01 08:32:30 -0700
comments: true
categories: []
---

# The Set-Up

> Johnny Hooker: Sometime after 2:00, a guy's gonna call on that phone there and give you the name of a horse.
> 

Imagine yourself, perhaps a typically-well-paid, tech-savvy professional, on the job hunt. You've been looking for a while with no luck; the market just sucks right now.

A recruiter reaches out on LinkedIn, and it seems to be a *perfect* opportunity, tailored exactly to your best skills. 

The company is one you've heard about; it's known to be a great place to work. They also pay pretty well compared to your previous job.

Of course you're quite stoked, and agree to some interviews. You have an initial screening call that seems to go well.  They mention that their interviews are under a standard, simple NDA and promise to send it to you over one of those legaltech SaaS startup platforms: you get the email, and after navigating their SSO system (enterprise software, amirite?) you see what is, yep, a pretty simple NDA, and sign it.

The interviews go great. The interviewers are warm, welcoming, and you look forward to getting to work with them more. Everything they say about the company sounds amazing.

And then you get the bad news: someone else got the job. Oh well. They did, however, enjoy talking to you and might reach out for future similar opportunities. Anyway, back to the grind.

Six months later, you learn this was all a scam. Your identity has been stolen, and thousands have been spent on credit cards opened in your name. You no longer have access to your email. Your brokerage account has been partially drained. It's going to take months to disentangle this, and you're likely not going to get everything back.

As you are discovering this, you're still bewildered as to how this happened. You never expected this type of thing to happen to *you*; you're well versed with keeping yourself secure on the internet and not prone to common scams.

# The Hook

> Henry Gondorff: You can't do it alone, you know. It takes a mob of guys like you and enough money to make them look good.

The point of attack was the login to the signing platform: your Google/iCloud/whatever account got phished while your guard was down when you did what appeared to be a "sign in with &lt;service&gt;" login to their signing platform. The attackers kept silent access to the account and monitored your patterns, looking for interesting ways to take advantage of this access. They downloaded all of your cloud files and used the account to log in to various other sites. They used everything they knew about you to open credit cards in your name.

This is pretty scary already, but the attack above had an additional facet making it much more scary, while also much harder to carry out: they managed to drain funds.

Modern financial systems have a lot of protection against hijacked accounts: most scams targeting money involve convincing someone to voluntarily transfer a bunch of money in an irreversible or untraceable way, and a tech-savvy professional is less likely to be the target of that. Involuntarily transfering your money would involve initiating a bank transfer via online banking. This would potentially be noticed, transfers take a few days, and the target account could be traced due to KYC regs. Furthermore, banking sites often use 2FA and text the user when there is a login.

But one can work around a lot of this. Someone with persistent, undetected access to your email and accounts may notice, for example, that you have paycheck money autotransfering to a brokerage account that you don't seem to touch or log in to often (by the dearth of "login detected to foo.com" emails). They might gain access to it by resetting your password (and deleting the notification), add a transfer account, and establish a pattern of usage making small transfers. Maybe they can wait for you to be on vacation, because they know when that is: they have your calendar!

Tracing can be thwarted by using (unsuspecting) [money mules] are a preexisting way to avoid being traced after a fraudulent transfer. 

Hopefully, I have convinced you that such an attack is at least plausible. But of course, this is a *lot* of effort, needing multiple people coordinating together and monitoring things, for a payoff that might not happen. This certainly feels *unlikely* as something that might happen.

Well, I left out one part. This entire attack was orchestrated and carried out by an LLM.

An LLM which could research everything about you; craft a tailored attack, put together all the things that would be needed to make this seem plausible (a LinkedIn account, a fake document signing website, a plausible-looking domain to send emails from), and synthesize all text, audio and video interactions. An LLM which, after gaining access to your account, could monitor it and find the best ways to make use of that access, whether it be worming its way into your brokerage, racking up huge cloud spends on AWS, taking all your crypto, or even ransoming your decades of precious data from your now-stolen, likely-wiped account.



 [money mules]: https://www.fbi.gov/how-we-can-help-you/scams-and-safety/common-frauds-and-scams/money-mules


# The Tale

> Henry Gondorff: It's not like playing winos in the street. You can't outrun Lonnegan.

For quite a while now, you could broadly categorize scams into two buckets: cheap, easy-to-run spray-and-pray scams hoping to ensnare the less savvy, and expensive, *targeted* scams, aimed at people worth the trouble. And usually "people worth the trouble" is more about *organizational* power someone holds rather than going after personal savings, like [this $25M scam in Hong Kong][arup] where an employee of a company was convinced to transfer company funds.

Spray-and-pray scams are cheap because they often spend no effort in convincing you. In fact, the "Nigerian Scammer" trope exists because [for scammers running scams against less-savvy individuals, it is highly desirable that the more-savvy individuals self-select out of their pipeline as early as possible][nigerian-why]. Emails are free, but the subsequent work to correspond with and scam a mark is not.

Tech-savvy people are, by and large, not prone to these scams. One can pick up a bunch of computer security best practices, paired with a rough understanding of the capabilities inherent in the system[^1], and be reasonably secure against this stuff.

However, with respect to more sophisticated scams, most people aren't "worth the trouble", or at least think they aren't. Most people don't have $25M buttons available to them at work.

Sure, many professionals have enough savings that it would make sense to mount a sophisticated scam, but also the likelihood of it happening to them is still slight: A scam that takes that amount of effort takes a lot of setup time and can't just be scaled up; you need people with the sophistication to run this scam willing to become criminals, and that just doesn't parallelize.

Sophisticated attacks like this against individual wealth [do happen though][the-cut] [^2]. "It can't happen to me" isn't the right framing, but "it's unlikely this will happen to me" is.


Quoting [James Mickens](https://www.usenix.org/system/files/1401_08-12_mickens.pdf):

> Basically, you’re either dealing with Mossad or not-Mossad. If your adversary is not-Mossad, then you’ll probably be fine if you pick a good password and don’t respond to emails from ChEaPestPAiNPi11s@virus-basket.biz.ru. If your adversary is the Mossad, YOU’RE GONNA DIE AND THERE’S NOTHING THAT YOU CAN DO ABOUT IT. The Mossad is not intimidated by the fact that you employ `https://``. If the Mossad wants your data, they’re going to use a drone to replace your cellphone with a piece of uranium that’s shaped like a cellphone, and when you die of tumors filled with tumors, they’re going to hold a press conference and say “It wasn’t us” as they wear t-shirts that say “IT WAS DEFINITELY US,” and then they’re going to buy all of your stuff at your estate sale so that they can directly look at the photos of your vacation instead of reading your insipid emails about them.




The core idea here is, adversary capability is bimodal, clustered at "untargeted × cheap" and "targeted × expensive". And running targeted attacks *at scale* just doesn't work easily.

Correction, adversary capability *was* bimodal. LLMs fill the middle of the distribution. They're pretty cheap: [A 2024 paper][heiding] found that LLMs tasked with spearphishing cost around 4¢ per email. The interview scam laid out above is more involved and more expensive, but likely still worth it, and 2026 LLMs are leaps and bounds better.

The more important and scary thing is that _this scales_: you can be running thousands of these scams at once! You could probably even have LLMs research individuals and serve them up with bespoke scams designed for that individual's dossier.

We are now in a world where scams can be run in a `for` loop.


 [nigerian-why]: https://web.archive.org/web/20120622161722/http://research.microsoft.com/pubs/167719/WhyFromNigeria.pdf
 [arup]: https://www.cnn.com/2024/02/04/asia/deepfake-cfo-scam-hong-kong-intl-hnk/index.html
 [the-cut]: https://www.thecut.com/article/amazon-scam-call-ftc-arrest-warrants.html
 [heiding]: https://arxiv.org/abs/2412.00586
 [^1]: Remember, phone numbers in Caller ID and `from:` headers in emails can be spoofed!
 [^2]: Also worth reading Patrick McKenzie's [excellent followup investigative journalism](https://www.bitsaboutmoney.com/archive/two-americas-one-bank-branch/) on that article.


# The Wire

TODO capabilities

this is real, and the ceiling keeps moving

all of these capabilities exist *today*

capabilities + don't-assume-the-gaps-are-permanent + the supply chain

# The Shut-Out

TODO 

authenticity signals are dying + the human cost

liar's dividend


# The Sting

where to go from here.

Recently I was doing a financial transaction with a person I know, and ended up ....    

# TODOS

Sting quote

 When the marginal cost of a personalized week-long con approaches the cost of a spam email, the question stops being "am I worth targeting?" and becomes "am I in the loop's address list?" — and everyone is.

 The Set Up
 The Hook
 The Tale
 The Wire
 The Shut-Out
 The Sting