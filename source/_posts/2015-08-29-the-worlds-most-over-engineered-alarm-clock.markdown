---
layout: post
title: "The world's most over-engineered alarm clock"
date: 2015-08-29 00:08:59 +0530
comments: true
categories: programming
---


A few weeks ago, I set up my Raspberry Pi as a music server so that I could listen to music without
having to deal with keeping my laptop in a certain corner of the room.

After setting it all up, it occurred to me: "I can do much more with this!".

Waking up to go to class in the morning is always a challenge for me. It's not that I don't wake up
&mdash; I often wake up, cancel all the alarms, and go back to bed. Half-asleep me somehow has the
skill to turn off alarms, but not the discipline of going to class[^1]. I've tried those apps that
make you do math before you can cancel the alarm, and I'm able to do the math and go back to sleep
without fully waking up in the process (Hey, I'm a physics student; math is what we do!).

So I decided to create an alarm clock. Not just any alarm clock, the most overengineered alarm clock
I can think of.

It consists of the Pi connected to a speaker and kept in a hard-to-reach area of the room. The Pi is
on a DHCP network. Every night, I ssh to the Pi, set the volume to full, and run a script which,
using `at` and `mpg123`, will schedule jobs to run around the desired time of waking up. First,
there will be a few pieces of soothing music (either violin music or parts of the _Interstellar_
OST) run once or twice, a while before the time of waking up. Close to the time of waking up, there
are a bunch of jobs where each one will run a string of annoying music. In my case, it's the
Minions' banana song followed by Nyan Cat (I sometimes add more to this list).

So far so good.

Now, the soothing music gives asleep-me me a chance to surrender and wake up _before_ the Nyan Cat
begins, and often fear of Nyan Cat is a pretty good motivator to wake up. If I don't wake up to
the soft songs, the annoying ones invariably work.

At this stage I'm still pretty groggy and have the intense urge to go back to bed. However, turning
off the alarm isn't simple. Since it's in a hard to reach area of the room, I can't just turn it
off. I need to get up, sit in my chair, and turn on the laptop (which is hibernated/suspended), and
kill it via ssh.

This needs me to:

 - `nmap` the network to find the Pi (I'm the only one on this subnet who uses `ssh`, so this just needs a port filter)
 - `ssh` into the Pi, remembering the password (I haven't done this yet but I could further complicate things by changing the password often to reduce muscle-memory)
 - `killall mpg123` to kill the currently playing song
 - Cancel the remaining `at` jobs. This can be done with `atq` + `atrm` for every job (tedious and long), or with `awk`. If I've already fully woken up, I'm able to do the `awk` one, otherwise half-asleep me ends up doing the brute-force one, which is enough manual typing to shake the remaining bits of sleepiness off.

After this whole process, it's pretty much guaranteed that I'm fully awake -- there's no going back now!

So far it's worked pretty well (both when I've slept on time and when I haven't). The first ten minutes after this I'm rather annoyed, but after that I'm happy I woke up. If half-asleep me
eventually gets the muscle memory to get past this process, I should probably be able to tweak it
to add more complexity or change the way it works.

Of course, having an arms race with oneself probably isn't the best way to solve this problem. I
suspect I'll go back to regular alarms in a month or so, but it's a fun experiment for now.

However, by the time I'm done with this alarm clock, I'll either be waking up on time, or I'll be
able to Linux in my sleep, which is a win-win!

 [^1]: As a fourth year student the fully-awake me also has a bit of trouble with this ;)