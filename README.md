# Sushi Buddy

A tray / menu bar app: pick **Motivate me** and a sushi in a propeller hat flies across the screen
your mouse is on, hovers to say something encouraging, and flies off. The overlay ignores clicks, so
it never gets in the way.

| | macOS | Windows |
|---|---|---|
| Folder | `mac/` (Swift, SwiftUI + AppKit) | `windows/` (Electron) |
| Trigger | menu bar icon → Motivate me | tray icon: left click, or right click → Motivate me |
| On a timer | menu bar icon → Auto-motivate | tray icon → Auto-motivate |
| At login | menu bar icon → Launch at Login | tray icon → Start with Windows |
| Build | `mac/scripts/build-app.sh` (Xcode) | `cd windows && npm install && npm run package` |
| Output | `~/Applications/Sushi Buddy.app` | `windows/dist/Sushi-Buddy-windows-{x64,arm64}.zip` |

**Auto-motivate** flies on its own every 15 or 30 minutes, every hour, or every 2 or 4 hours, counted
from when you pick it (and from each launch). The choice is kept: in the app's defaults on macOS
(`autoMotivateSeconds`), in `%APPDATA%\Sushi Buddy\settings.json` on Windows.

**Focus is respected:** while a macOS Focus (Do Not Disturb, Work, …) or Windows Do not disturb /
Focus assist is on, Auto-motivate skips its turn. **Motivate me** still flies, since you asked. On
macOS the first time Auto-motivate is switched on, the app asks to see your Focus status; if that is
declined it cannot tell, and flies as usual. Both apps answer `--focus-status` with what they see.

**Updates:** both apps check this repo's latest GitHub release quietly at launch and once a day. When
there is a newer one, the menu's **Check for Updates…** becomes **Update to 1.x…**, which opens the
download for your machine in the browser; **Check for Updates…** itself says what it found. Nothing
installs by itself: unzip the download over the old app. A release must keep the asset names
(`Sushi-Buddy-macOS-arm64.zip`, `Sushi-Buddy-windows-{x64,arm64}.zip`) and a `v1.2.0`-style tag for the
apps to find it. Tests: `cd mac && swift test`, `cd windows && npm test`.

Both apps share `Resources/`: the art layers and `motivation.json`, the lines the sushi says.
`windows/flight.js` is a line-for-line port of `mac/Sources/SushiBuddy/Flight.swift`, so both fly the
same path; change one, change the other.

## Installing

**macOS (Apple Silicon):** run `mac/scripts/build-app.sh`; it installs to `~/Applications` and starts
the app.

**Windows 10/11:** unzip the zip for your machine (x64, or arm64 for ARM laptops) anywhere and run
`Sushi Buddy.exe`. The exe is not code-signed, so SmartScreen shows "Windows protected your PC" the
first time: **More info → Run anyway**. Packaging off Windows leaves the exe with Electron's own icon;
the tray icon is the sushi either way.

## Handy flags

- `--fly`: fly once at launch. On Windows a second launch with `--fly` reaches the running app, so a
  shortcut with it works as a trigger.
- `--preview <file.png>`: render moments of a flight without showing anything (Windows build:
  `--at 0.9,3,5.9` picks the seconds).
- `--launch-at-login on|off`: set it from a script (macOS also takes `status`). On Windows it is the
  `Run` registry entry for the exe where it is now, so turn it on again after moving the folder.
- `--focus-status`, `--check-updates`: say what the app sees.

## Art

`Art/sushi.svg` is the original. `Art/body.svg` (no propeller blades, no `?`) and
`Art/propeller.svg` (blades only) share its 60×60 viewBox and are rendered to `Resources/body.png` and
`Resources/propeller.png` at 1200 px; both apps spin the blades around the stem with a 3D rotation.
