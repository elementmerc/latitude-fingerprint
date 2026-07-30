# Getting the fingerprint reader working on a Dell Latitude running Ubuntu

## How I got here

I've been juggling a few projects lately, and somewhere along the way it dawned
on me that I'd be better off living on Linux full time instead of bouncing in
and out of WSL. I had a gaming machine sitting there, so I made the switch
permanent. Ubuntu was the obvious pick. The other candidate was Kali, and as
much as I love it for pentesting, it is not what you want for ordinary
day-to-day computing.

One thing didn't survive the move: my fingerprint reader. Ubuntu could see the
sensor, it just wouldn't let me use it. This is the part where some people say
"it's a small thing, just ignore it". Maybe I should have listened. But it
nagged at me every single time I logged in and typed my password out by hand,
so I decided I'd build whatever driver or glue the thing needed to work.

## The hail mary, and how drivers actually reach your machine

I had never built anything like this before. But as my cousin likes to say,
necessity is the mother of invention, and my slightly unhealthy need for that
sensor to work had me attempting the unnecessary. I used Claude Code (yes, I'm
biased towards Anthropic; my experience with them has been nothing but good) to
research how fingerprint sensors work, why some operating systems ship drivers
and others don't, and what it would take to write my own.

Before the story goes further, here is the distilled version of how a driver
gets onto your computer, or doesn't. I learned this in under 72 hours, so
correct me where I'm wrong. Hardware makers like Dell, HP and Lenovo write the
drivers for their own kit and agree with OS vendors on how those drivers may be
shipped. On Windows this is a smooth road, because Windows owns the
overwhelming majority of the consumer market, so painless driver installation
is a no-brainer for everyone involved. On Linux it is bumpier: some vendors help
where they can, others (NVIDIA, cough) can be a pain. Common parts like
displays, keyboards and sound tend to work out fine because Linux drivers exist
either way; the trouble starts with the specialised bits, like oddball function
keys, custom hardware, or in my case a fingerprint reader.

```
  Hardware maker (Dell / Broadcom)
        |  writes the driver, sets the licence terms
        v
  Agreement with the OS vendor
        |
        +--> Windows: shipped automatically (huge market, every incentive)
        |
        +--> Linux: depends on goodwill and licensing
                     |
        common parts (display, keyboard) --> just work
        niche parts (fingerprint) ---------> often fall through the cracks
```

Linux distributions usually paper over this with a team that prioritises what
most people need, or by being open enough that the community fills the gaps. A
fingerprint reader on a Dell Latitude hadn't made anyone's priority list, which
is fair enough: when I opened the thread on Launchpad (Canonical's GitHub-like
home for Ubuntu's code, bugs and package builds), I was only the third person to
register the same complaint, on a discussion that had been opened the year
before.

Back to the moonshot. When I first asked what it would take, the answer involved
reverse-engineering parts of the hardware and a timeline measured in months. I
was half asleep and wanted something sooner (and legal), so I asked it to dig
into my specific situation instead. It came back having corrected itself: I
didn't need to build anything from scratch. Dell's driver already existed,
Canonical was already permitted to distribute it, and it was sitting in their
archive. The catch was that it had only ever been wired up for Ubuntu 22.04, in
a special OEM channel meant for that release. There was even someone on it: a
Canonical engineer, Yao Wei, had been packaging the driver. The public bug
thread had been quiet since March 2025, though his packaging work carried on in
his own archive; it just hadn't reached Ubuntu's normal archive, and it didn't
cover the newest release, 26.04, which happens to be what I run. So I decided to
take matters into my own hands. What could possibly go wrong?

## Building it (mistakes and all)

It turned out to be surprisingly doable with an agentic AI in the loop. My
background in computer science and security had me thinking about the things
that matter: the specification, a mental model of how it should all behave, how
it copes when things go wrong, and testing. The actual coding was mostly
Claude's. What we built is a delivery mechanism. It does not contain the driver;
it fetches Broadcom's driver, checks it against a checksum recorded in the
project so you can see it arrived intact, and installs it cleanly. It comes from
Canonical's OEM archive, or from Broadcom's own download if Canonical's copy
can't be reached. Either way it travels straight from them to you. We never
bundle it or re-host it.

We both made mistakes. The first time the agent pushed to the repository, it
included some internal working files and build artefacts that had no business
being public. That one is on me too: I should have reviewed what was going out
before it went out. And while the very first install worked and my sensor
sprang to life, I nearly didn't test hard enough to know whether it would hold
up on other Latitudes running other versions of Ubuntu. I came close to shipping
something that worked only on my desk. Docker helped there: throwaway containers
on clean 24.04 and 26.04 confirmed the packaging, the download, the checksum, the
install and the removal all behave on a machine that isn't mine. What a container
can't do is touch a sensor, so the enrolment half is still only proven on my own
laptop.

## Try it

If you have the same sensor (a Broadcom ControlVault 3, USB id `0a5c:5843`) on
Ubuntu 24.04 or 26.04:

```sh
sudo add-apt-repository ppa:elementmerc/latitude-fingerprint
sudo apt update
sudo apt install libfprint-2-tod1-broadcom-installer
```

Then enrol a finger and test it:

```sh
fprintd-enroll "$USER"
fprintd-verify
```

The first install flashes the sensor's firmware, which makes it reset on the USB
bus. If that first enrol says "No such device", reboot once and run it again; it
won't re-flash, and enrolment then works normally.

One good thing came of posting on the bug: Yao Wei replied. He confirmed 5.15.285
is the newest build Broadcom has put out, explained he can't promise future ones
for 26.04 and beyond, and pointed me at the packaging's `debian/watch` file. That
pointer is why the project now knows about Broadcom's own download and uses it as
a second source when Canonical's copy is unreachable. He also said he'd chase the
uploaders about getting it into the archive properly, which is where it belongs.

The source, the packaging, and prebuilt downloads live on
[GitHub](https://github.com/elementmerc/latitude-fingerprint). I've also left a
note on the [Launchpad bug](https://bugs.launchpad.net/ubuntu/+bug/2099655),
asking whether this can be shipped properly to the other two Latitude owners out
there with the same problem. (It is really far more than two. I was just the
third to complain.)

## Lessons learned

So a grand total of three people on a bug thread share the problem I've now got
a package for, and honestly, it was worth it. I learned how drivers reach your machine,
I got to make something small that helps the open-source community, and I came
out the other side a bit better at thinking about whole systems rather than just
the code in front of me. Catch you in the next one. Till then, cheers.
