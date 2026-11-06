// Whether Windows "Do not disturb" / Focus assist is on, so Auto-motivate can hold off.
// "Motivate me" is the person asking, so it flies regardless.
//
// Windows has no public API for this; the shell publishes the active quiet-hours
// profile as a WNF state (0 = off, 1 = priority only, 2 = alarms only), read here
// through ntdll from PowerShell, which every Windows 10/11 has.
const { execFile } = require('node:child_process')

const SCRIPT = `
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SushiWnf {
  [DllImport("ntdll.dll")]
  public static extern int NtQueryWnfStateData(ref ulong stateName, IntPtr typeId, IntPtr explicitScope,
    out uint changeStamp, byte[] buffer, ref uint bufferSize);
}
'@
$state = [UInt64]0x0D83063EA3BF1C75
$buffer = New-Object byte[] 4
$size = [UInt32]4
$stamp = [UInt32]0
$status = [SushiWnf]::NtQueryWnfStateData([ref]$state, [IntPtr]::Zero, [IntPtr]::Zero, [ref]$stamp, $buffer, [ref]$size)
if ($status -ne 0) { exit 1 }
[BitConverter]::ToInt32($buffer, 0)
`

/** The active quiet-hours profile (0 = off), or null where it cannot be read. */
function focusProfile() {
  if (process.platform !== 'win32') return Promise.resolve(null)
  const encoded = Buffer.from(SCRIPT, 'utf16le').toString('base64')
  return new Promise(resolve => {
    execFile(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', encoded],
      { windowsHide: true, timeout: 15000 },
      (error, stdout) => {
        const profile = Number.parseInt(String(stdout).trim(), 10)
        resolve(error || Number.isNaN(profile) ? null : profile)
      },
    )
  })
}

/** True while a Focus is on. Unreadable counts as off, so a failed check never silences the app for good. */
async function isFocused() {
  return ((await focusProfile()) ?? 0) > 0
}

module.exports = { focusProfile, isFocused }
