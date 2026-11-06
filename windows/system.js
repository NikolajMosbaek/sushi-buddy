// What Windows says about the moment: Do not disturb / Focus assist, a full-screen app or
// presentation, and whether the microphone or camera is in use (a call). One PowerShell run
// answers all four, so a check costs one process.
//
// Do not disturb has no public API: the shell publishes the active quiet-hours profile as a
// WNF state (0 = off, 1 = priority only, 2 = alarms only), read through ntdll.
// SHQueryUserNotificationState answers 2 (busy: a full-screen app), 3 (full-screen Direct3D)
// or 4 (presentation mode) while presenting. Windows marks an app using the microphone or
// camera with LastUsedTimeStop = 0 under CapabilityAccessManager\ConsentStore.
const { execFile } = require('node:child_process')

const SCRIPT = `
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SushiSystem {
  [DllImport("ntdll.dll")]
  public static extern int NtQueryWnfStateData(ref ulong stateName, IntPtr typeId, IntPtr explicitScope,
    out uint changeStamp, byte[] buffer, ref uint bufferSize);
  [DllImport("shell32.dll")]
  public static extern int SHQueryUserNotificationState(out int state);
}
'@
$focus = -1
$state = [UInt64]0x0D83063EA3BF1C75
$buffer = New-Object byte[] 4
$size = [UInt32]4
$stamp = [UInt32]0
if ([SushiSystem]::NtQueryWnfStateData([ref]$state, [IntPtr]::Zero, [IntPtr]::Zero, [ref]$stamp, $buffer, [ref]$size) -eq 0) {
  $focus = [BitConverter]::ToInt32($buffer, 0)
}
$notification = -1
$quns = 0
if ([SushiSystem]::SHQueryUserNotificationState([ref]$quns) -eq 0) { $notification = $quns }
function InUse($kind) {
  $root = "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\$kind"
  if (-not (Test-Path $root)) { return 0 }
  foreach ($key in Get-ChildItem $root -Recurse -ErrorAction SilentlyContinue) {
    $entry = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
    if ($entry.LastUsedTimeStart -and $entry.LastUsedTimeStop -eq 0) { return 1 }
  }
  return 0
}
"$focus $notification $(InUse 'microphone') $(InUse 'webcam')"
`

/** Reads the script's "focus notification microphone camera" line; -1 or garbage reads as unknown (null). */
function parseSystem(stdout) {
  const numbers = String(stdout).trim().split(/\s+/).map(part => (/^-?\d+$/.test(part) ? Number(part) : null))
  const known = index => (numbers[index] == null || numbers[index] < 0 ? null : numbers[index])
  const flag = index => (known(index) == null ? null : known(index) === 1)
  return { focusProfile: known(0), notificationState: known(1), microphone: flag(2), camera: flag(3) }
}

/** The signals the quiet rules read. Anything unreadable counts as not happening, so a failed check never silences the app for good. */
function signalsFrom(system) {
  return {
    focus: (system.focusProfile ?? 0) > 0,
    presenting: [2, 3, 4].includes(system.notificationState),
    call: system.microphone === true || system.camera === true,
  }
}

function readSystem() {
  if (process.platform !== 'win32') {
    return Promise.resolve({ focusProfile: null, notificationState: null, microphone: null, camera: null })
  }
  const encoded = Buffer.from(SCRIPT, 'utf16le').toString('base64')
  return new Promise(resolve => {
    execFile(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', encoded],
      { windowsHide: true, timeout: 15000 },
      (error, stdout) => resolve(parseSystem(error ? '' : stdout)),
    )
  })
}

module.exports = { parseSystem, readSystem, signalsFrom }
