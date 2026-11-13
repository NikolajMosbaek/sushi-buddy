# Privacy

Sushi Buddy collects nothing about you unless you ask it to. It has no accounts, no ads and no
tracking across apps or sites. From version 1.8 there is one switch that sends me anything at all, **Share anonymous usage
statistics**, and it is off until you turn it on. What it sends is below.

## What it looks at, on your computer only

To hold off at the right moments (the quiet rules in Settings), it checks while it runs:

- whether a Focus or Do not disturb is on (macOS asks your permission once)
- whether the microphone or camera is in use: only whether, never what they pick up
- whether the app in front fills the screen or is presenting
- how long since you last used the keyboard or mouse, and whether the screen is locked

The answers are used there and then, and not kept.

## What it keeps, on your computer only

- your settings
- your streak: how many days in a row, and the last day
- whether you have seen the tour, and whether it has asked about usage statistics
- your own lines, if you edit them
- while usage statistics are on: their random ID, today's counts and the settings you have changed

On macOS that is the app's defaults (`com.nsscode.SushiBuddy`) and
`~/Library/Application Support/Sushi Buddy/`; on Windows, `%APPDATA%\Sushi Buddy\`. Delete those
along with the app and nothing is left.

## Claude Code and scripts

The Claude Code plugin and your own scripts talk to Sushi Buddy on `127.0.0.1`, which only programs on
your own computer can reach. Of each Claude Code event it uses the event's name, the session and the
name of the project folder (for "Claude's done in my-app!"). Everything else in the event, such as
your prompt, is ignored and not stored.

## The internet

Besides usage statistics, if you turn them on, the only thing Sushi Buddy does online on its own is
the update check: at launch and once a day it
asks GitHub for the latest release (on a Mac, its update feed, and then the update itself when there
is one). Nothing about you goes along with them. GitHub sees those requests like any
other, including your IP address, under the [GitHub General Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).
To switch it off: Settings → General → **Check for updates automatically**.

**Tip the Sushi…** and **What's New**'s release notes only open a page in your browser, as **Update
to…** does on Windows.

## Usage statistics, only if you turn them on

**Settings → General → Share anonymous usage statistics** is off until you turn it on. The tour asks
about it once, and so does **What's New** if the tour never did. While it's on, Sushi Buddy sends one
summary a day to [TelemetryDeck](https://telemetrydeck.com), an analytics service from Germany, so I
can see how many people use Sushi Buddy and which settings they choose. A summary has:

- the app's version, the system (macOS or Windows, its version and the processor type) and how the app
  was installed (Homebrew, a download or winget)
- the value of every setting, how many differ from their defaults, and which you have ever changed
- since the last summary: how many times the sushi flew, by what started it (the menu, the shortcut,
  a script, Auto-motivate, a break reminder, welcome back, a Pomodoro or Claude Code), how many
  automatic flights each quiet rule held back, how many pets, and how many times the app ended without
  quitting while the computer stayed on

It never has anything you typed: not your lines, project or folder names, Claude Code events or what
a script sent. It carries no name, email address or account. **Show What's Sent…** next to the switch
shows the exact request.

To tell one person's summaries apart, turning the switch on makes a random ID that has nothing to do
with you or your computer. Only a hash of it leaves your computer, and TelemetryDeck hashes it again
before storing it. Turning the switch off stops the summaries at once and deletes the ID and the counts
from your computer; turning it on again makes a new ID. TelemetryDeck receives each summary like any
other request, including your IP address, under its
[privacy policy](https://telemetrydeck.com/privacy/).

## Tips

Tips go through Ko-fi and PayPal, on their sites and under their privacy policies. They show me the
tip and what comes with it, such as the name, email address and message you leave. I use that only
to say thank you and for my own records, and never share it.

## Questions

Open an issue at [github.com/NikolajMosbaek/sushi-buddy](https://github.com/NikolajMosbaek/sushi-buddy/issues).
Sushi Buddy is made by Nikolaj Søgaard Simonsen.

Changes to this page show in its history on GitHub. Last updated 12 November 2026.
