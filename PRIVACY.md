# Privacy

Sushi Buddy collects nothing about you. It has no accounts, no analytics, no ads and no tracking,
and it never sends anything to me.

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
- whether you have seen the tour
- your own lines, if you edit them

On macOS that is the app's defaults (`com.nsscode.SushiBuddy`) and
`~/Library/Application Support/Sushi Buddy/`; on Windows, `%APPDATA%\Sushi Buddy\`. Delete those
along with the app and nothing is left.

## Claude Code and scripts

The Claude Code plugin and your own scripts talk to Sushi Buddy on `127.0.0.1`, which only programs on
your own computer can reach. Of each Claude Code event it uses the event's name, the session and the
name of the project folder (for "Claude's done in my-app!"). Everything else in the event, such as
your prompt, is ignored and not stored.

## The internet

The only thing Sushi Buddy does online on its own is the update check: at launch and once a day it
asks GitHub's API for the latest release. GitHub sees that request like any other, including your IP
address, under the [GitHub General Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).
To switch it off: Settings → General → **Check for updates automatically**.

**Tip the Sushi…**, **What's New**'s release notes and **Update to…** only open a page in your browser.

## Tips

Tips go through Ko-fi and PayPal, on their sites and under their privacy policies. They show me the
tip and what comes with it, such as the name, email address and message you leave. I use that only
to say thank you and for my own records, and never share it.

## Questions

Open an issue at [github.com/NikolajMosbaek/sushi-buddy](https://github.com/NikolajMosbaek/sushi-buddy/issues).
Sushi Buddy is made by Nikolaj Søgaard Simonsen.

Changes to this page show in its history on GitHub. Last updated 8 November 2026.
