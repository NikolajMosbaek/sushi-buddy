// A small HTTP endpoint on 127.0.0.1 for Claude Code's hooks and your own scripts.
// The same rules as mac/Sources/SushiBuddy/Listener.swift.
//
//   POST /claude   a Claude Code hook event (its JSON as the body)
//   POST /fly      fly now; the body is {"message": "…"}, plain text, or empty for a random line
//   GET  /         "Sushi Buddy 1.4.0", to check it is listening
//
// Only this computer can reach it. A web page could still try to post to it from the
// browser, so any request carrying an Origin header (every browser sends one on a
// cross-site POST) or a Host other than this address is refused.
const http = require('node:http')

const PORT = 7874
const MAX_BODY = 64 * 1024
const MAX_MESSAGE = 140

/** Which route a request may take: { status, route }. Header names are lower case, as Node gives them. */
function vet({ method, url, headers }, port) {
  if (headers.origin !== undefined) return { status: 403 }
  const host = String(headers.host ?? '').toLowerCase()
  if (host !== `127.0.0.1:${port}` && host !== `localhost:${port}`) return { status: 403 }
  const route = String(url).split('?')[0]
  if (method === 'GET' && route === '/') return { status: 200, route: 'hello' }
  if (method === 'POST' && (route === '/claude' || route === '/fly')) return { status: 204, route: route.slice(1) }
  return { status: 404 }
}

/** The message a /fly asks for, cleaned up, or null for a random line. */
function flyMessage(body) {
  let text = String(body ?? '')
  try {
    const parsed = JSON.parse(text)
    text = parsed && typeof parsed === 'object' ? String(parsed.message ?? '') : String(parsed)
  } catch {
    // Not JSON: the body itself is the message.
  }
  const clean = Array.from(text.replace(/[\u0000-\u001f\u007f]/g, ' ').trim()).slice(0, MAX_MESSAGE).join('')
  return clean === '' ? null : clean
}

/** Starts listening. Resolves to { server } or { error } (a port in use, say); handlers get parsed bodies. */
function listen(port, { version, onClaude, onFly }) {
  const server = http.createServer((request, response) => {
    const verdict = vet(request, port)
    if (verdict.route === 'hello') {
      response.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' })
      response.end(`Sushi Buddy ${version}\n`)
      return
    }
    if (!verdict.route) {
      response.writeHead(verdict.status)
      response.end()
      request.resume()
      return
    }
    const chunks = []
    let size = 0
    request.on('data', chunk => {
      size += chunk.length
      if (size > MAX_BODY) {
        response.writeHead(413)
        response.end()
        request.destroy()
      } else {
        chunks.push(chunk)
      }
    })
    request.on('end', () => {
      if (response.writableEnded) return
      const body = Buffer.concat(chunks).toString('utf8')
      if (verdict.route === 'claude') {
        let event
        try {
          event = JSON.parse(body)
        } catch {
          response.writeHead(400)
          response.end()
          return
        }
        response.writeHead(204)
        response.end()
        onClaude(event)
      } else {
        response.writeHead(204)
        response.end()
        onFly(flyMessage(body))
      }
    })
  })
  return new Promise(resolve => {
    server.once('listening', () => resolve({ server }))
    server.once('error', error =>
      resolve({ error: error.code === 'EADDRINUSE' ? `Port ${port} is in use by another app.` : error.message }),
    )
    server.listen(port, '127.0.0.1')
  })
}

module.exports = { MAX_BODY, PORT, flyMessage, listen, vet }
