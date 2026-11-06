# Sushi Buddy

![The propeller-hat sushi flies in, says "You're on a roll!" and flies off](docs/sushi-buddy.gif)

A tray / menu bar app: pick **Motivate me** and a sushi in a propeller hat flies across the screen
your mouse is on, hovers to say something encouraging, and flies off. It can also fly on its own:
on a timer, when a break is due, when you come back, when a Pomodoro ends, or when Claude Code
finishes a long turn. Everything it does on its own is a switch in **Settings**, and it holds off
while you're in a Focus, on a call, presenting or away.

| | macOS | Windows |
|---|---|---|
| Folder | `mac/` (Swift, SwiftUI + AppKit) | `windows/` (Electron) |
| Fly now | menu bar icon → Motivate me, or ⌃⌥⌘S | tray icon: left click, or right click → Motivate me, or Ctrl+Alt+Shift+S |
| Settings | menu bar icon → Settings… (⌘,) | tray icon → Settings… |
| Build | `mac/scripts/build-app.sh` (Xcode) | `cd windows && npm install && npm run package` |
| Output | `~/Applications/Sushi Buddy.app` | `windows/dist/Sushi-Buddy-windows-{x64,arm64}.zip` |
| Tests | `cd mac && swift test` | `cd windows && npm test` |

## Installing

**macOS (Apple Silicon, macOS 14 or later)** with Homebrew:

```sh
brew tap nikolajmosbaek/sushi-buddy https://github.com/NikolajMosbaek/sushi-buddy
brew trust nikolajmosbaek/sushi-buddy   # Homebrew 7 and later only load taps you trust
brew install --cask sushi-buddy
```

Or download `Sushi-Buddy-macOS-arm64.zip` from the [latest release](https://github.com/NikolajMosbaek/sushi-buddy/releases/latest),
or build it yourself with `mac/scripts/build-app.sh`, which installs to `~/Applications` and starts it.
Until a release is notarized, macOS asks the first time: open it from System Settings → Privacy &
Security → **Open Anyway**.

**Windows 10/11:** download the zip for your machine (x64, or arm64 for ARM laptops) from the
[latest release](https://github.com/NikolajMosbaek/sushi-buddy/releases/latest), unzip it anywhere and
run `Sushi Buddy.exe`. The exe is not code-signed, so SmartScreen shows "Windows protected your PC" the
first time: **More info → Run anyway**. Each release also carries winget manifests
(`winget-manifests.zip`), ready to submit to winget.

## Settings

Every change applies at once. On macOS the settings are the app's defaults
(`defaults read com.nsscode.SushiBuddy`); on Windows they are `%APPDATA%\Sushi Buddy\settings.json`.
Both apps use the same names. Whatever flies or makes a sound on its own starts **off**; whatever only
holds flights back starts **on**.

| Setting | What it does | Starts |
|---|---|---|
| `autoMotivateSeconds` | **Auto-motivate**: fly every 15 or 30 minutes, every hour, or every 2 or 4 hours, counted from when you pick it | off |
| `breakReminderMinutes` | **Break reminders** after 30, 45, 60 or 90 minutes at the computer; five minutes away from the keyboard counts as a break | off |
| `welcomeBack` | **Welcome back** when you return after being away | off |
| `hotkey` | **Shortcut** for Motivate me: ⌃⌥⌘S, ⌃⌥S, ⌃⌥⌘M (Windows: Ctrl+Alt+Shift+S, Ctrl+Alt+S, Ctrl+Alt+Shift+M) or off | ⌃⌥⌘S / Ctrl+Alt+Shift+S |
| `flightPath` | **Flight path**: straight across, loop-the-loop, bounce, zigzag, or any at random | random |
| `petting` | **Pet the sushi**: click it mid-flight for an extra spin and hearts. Only the sushi takes the click; everything around it still passes through | on |
| `sound` | **Sound**: a chime as the bubble pops up, or a propeller whirr | off |
| `contextLines` | **Lines for the moment**: good morning, late night, Monday, Friday | on |
| `streaks` | **Streaks**: "Day 5 in a row!" on the first motivation of a day | on |
| `quietDuringFocus` | Hold off while a Focus / Do not disturb is on | on |
| `quietOnCalls` | Hold off while the microphone or camera is in use | on |
| `quietWhenPresenting` | Hold off while an app is full screen or presenting | on |
| `quietWhenAway`, `awayMinutes` | Hold off while the screen is locked or you've been idle 5, 10, 15 or 30 minutes | on, 10 |
| `listen` | Listen on `127.0.0.1:7874` for Claude Code and scripts | on |
| `claudeDone`, `claudeMinMinutes` | Cheer when Claude finishes a turn longer than 0, 1, 2, 5 or 10 minutes | on, 2 |
| `claudeNeedsYou` | Fly when Claude needs your permission | on |
| `pomodoroFocusMinutes`, `pomodoroBreakMinutes`, `pomodoroLongBreaks` | **Pomodoro** lengths, and a 15-minute break after every fourth | 25, 5, on |
| `checkForUpdates` | Check GitHub for a newer release at launch and once a day | on |

Launch at login (Start with Windows) is a switch there too; macOS and Windows keep that one themselves.

**Asked for vs automatic.** Motivate me, the shortcut, a Pomodoro you started and a script's `/fly`
always fly. Auto-motivate, break reminders, welcome back and Claude Code are automatic: they skip
their turn while a quiet rule holds, and Settings shows the last skip and why, so a quiet sushi
doesn't look broken. The Quiet section also shows what the app sees right now.

How the quiet rules see things: on macOS, Focus through the Focus status API (asked once), the
microphone through Core Audio's per-process input state, the camera through CoreMediaIO, and
presenting as the app in front filling a display. On Windows, one PowerShell run reads the
quiet-hours state, `SHQueryUserNotificationState` (full screen, Direct3D or presentation mode) and
which apps are using the microphone or camera. Nothing needs a permission besides Focus on macOS.

## Lines

`Resources/lines.json` holds a list of lines per occasion: `anytime`, `morning` (5–11),
`lateNight` (22–5), `monday`, `friday`, `streak`, `welcomeBack`, `break`, `claudeDone`,
`claudeNeedsYou`, `pomodoroDone` and `pomodoroBreakOver`. `{days}` becomes the streak and `{project}`
the folder Claude Code is working in.

**Edit Lines…** in Settings opens your own copy (`~/Library/Application Support/Sushi Buddy/lines.json`,
`%APPDATA%\Sushi Buddy\lines.json`). Each list you keep replaces that occasion's built-in lines, and an
occasion you delete keeps the built-in ones. It is read on every flight, so an edit counts from the
next one; if the file isn't valid JSON, the built-in lines are used and Settings says so.
**Reset to Built-in** moves your copy to the Trash.

## Claude Code

Install the hooks once, in a terminal:

```sh
claude plugin install sushi-buddy --marketplace NikolajMosbaek/sushi-buddy
```

(or `/plugin install sushi-buddy --marketplace NikolajMosbaek/sushi-buddy` inside Claude Code). The
plugin, in `claude-code/`, posts each prompt, stop and permission request to Sushi Buddy on
`127.0.0.1:7874` with `curl`, in the background: nothing leaves your computer, and when Sushi Buddy
isn't running the post just fails quietly. The app times each turn from prompt to stop, per session,
and cheers when one ran longer than the minimum you set. Without the plugin, the same hook in your own
`~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [{ "hooks": [{ "type": "command", "command": "curl", "async": true,
      "args": ["-s", "-m", "2", "--data-binary", "@-", "http://127.0.0.1:7874/claude"] }] }]
  }
}
```

Add the same entry under `UserPromptSubmit` (to time turns) and under `Notification` with
`"matcher": "permission_prompt"`.

**Scripts** can fly the sushi too: `curl -d 'Deployed! 🚀' http://127.0.0.1:7874/fly` (plain text,
`{"message": "…"}`, or an empty body for a random line). `curl http://127.0.0.1:7874/` answers with
the version. The listener only binds to `127.0.0.1`, and refuses any request with an `Origin` header or
a `Host` other than `127.0.0.1:7874` / `localhost:7874`, so a web page can't make it fly.

## Updates

Both apps check this repo's latest GitHub release quietly at launch and once a day (switch it off in
Settings). When there is a newer one, the menu's **Check for Updates…** becomes **Update to 1.x…**,
which opens the download for your machine in the browser; nothing installs by itself. Homebrew users
can `brew upgrade --cask --greedy sushi-buddy`.

## Releasing

Push a tag like `v1.4.0` (it must match `windows/package.json` and `mac/Info.plist`). The
**Release** workflow builds the Mac app on macOS and the Windows zips on Windows (with the sushi
icon and the app's name on the exe, so Task Manager says "Sushi Buddy"), writes the winget manifests,
and publishes them all as that tag's release, keeping the asset names the update checks look for
(`Sushi-Buddy-macOS-arm64.zip`, `Sushi-Buddy-windows-{x64,arm64}.zip`). Run the workflow by hand for
a dry run that only uploads the files as artifacts.

With a Developer ID (Apple Developer Program), add the secrets listed in
`mac/scripts/sign-and-notarize.sh` and the workflow signs and notarizes the Mac app too, which removes
the Gatekeeper prompt.

## Handy flags

- `--fly`: fly once at launch. On Windows a second launch with `--fly` reaches the running app, so a
  shortcut with it works as a trigger.
- `--settings`: open Settings at launch.
- `--status`: print what the quiet rules see (Windows shows it in a dialog).
- `--preview <file.png>`: render moments of a flight without showing anything. `--path loop` picks the
  path; on Windows `--at 0.9,3,5.9` picks the seconds and `--pets 2.2` pets it.
- `--preview-settings <folder>`: render the Settings window to PNGs.
- `--launch-at-login on|off`: set it from a script (macOS also takes `status`). On Windows it is the
  `Run` registry entry for the exe where it is now, so turn it on again after moving the folder.
- `--check-updates`: print what the update check finds.

## Art

`Art/sushi.svg` is the original. `Art/body.svg` (no propeller blades, no `?`) and
`Art/propeller.svg` (blades only) share its 60×60 viewBox and are rendered to `Resources/body.png` and
`Resources/propeller.png` at 1200 px; both apps spin the blades around the stem with a 3D rotation.
`Art/make-sounds.py` synthesises `Resources/chime.wav` and `Resources/whirr.wav`.
`windows/flight.js` is a line-for-line port of `mac/Sources/SushiBuddy/Flight.swift`, and the rules
(lines, quiet, Pomodoro, Claude Code, the listener) are tested case for case on both sides; change
one, change the other. `docs/make-gif.sh` remakes the GIF above.
