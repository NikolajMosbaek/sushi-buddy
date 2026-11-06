// Checks GitHub for a newer release. The same rules as mac/Sources/SushiBuddy/Updates.swift.
const REPOSITORY = 'NikolajMosbaek/sushi-buddy'

/** `v1.2.0` or `1.2` as numbers, or null when it is not a dotted version. */
function parseVersion(text) {
  const bare = String(text).replace(/^v/, '')
  const parts = bare.split('.').map(part => (/^\d+$/.test(part) ? Number(part) : NaN))
  return parts.some(Number.isNaN) ? null : parts
}

/** -1, 0 or 1, part by part, missing parts as 0. Unparseable counts as 0.0.0. */
function compareVersions(a, b) {
  const left = parseVersion(a) ?? [0]
  const right = parseVersion(b) ?? [0]
  for (let i = 0; i < Math.max(left.length, right.length); i += 1) {
    const difference = (left[i] ?? 0) - (right[i] ?? 0)
    if (difference !== 0) return Math.sign(difference)
  }
  return 0
}

/** The zip for this machine's architecture, or the release page when there is none. */
function pickDownload(release, arch) {
  const asset = (release.assets ?? []).find(one => one.name.toLowerCase().includes(`windows-${arch}.`))
  return asset?.browser_download_url ?? release.html_url
}

function outcome(release, current, arch) {
  const latest = String(release.tag_name).replace(/^v/, '')
  return parseVersion(latest) && compareVersions(latest, current) > 0
    ? { status: 'available', latest, url: pickDownload(release, arch) }
    : { status: 'up-to-date', latest }
}

async function check(current, arch = process.arch) {
  try {
    const response = await fetch(`https://api.github.com/repos/${REPOSITORY}/releases/latest`, {
      headers: { Accept: 'application/vnd.github+json', 'User-Agent': `SushiBuddy/${current}` },
    })
    if (!response.ok) throw new Error(`GitHub answered ${response.status}`)
    return outcome(await response.json(), current, arch)
  } catch (error) {
    return { status: 'failed', reason: error.message }
  }
}

module.exports = { check, compareVersions, outcome, parseVersion, pickDownload }
