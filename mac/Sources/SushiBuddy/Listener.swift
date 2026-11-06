import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "com.nsscode.SushiBuddy", category: "listener")

/// One HTTP/1.1 request, as far as this endpoint reads one: header names in lower case, body by Content-Length.
struct HTTPRequest: Equatable, Sendable {
    var method: String
    var target: String
    var headers: [String: String]
    var body: Data

    enum Parse: Equatable, Sendable {
        case incomplete
        case malformed
        case tooLarge
        case request(HTTPRequest)
    }

    static func parse(_ data: Data, maxBody: Int = Listener.maxBody) -> Parse {
        let bytes = Data(data)
        guard let end = bytes.firstRange(of: Data("\r\n\r\n".utf8)) else {
            return bytes.count > 16 * 1024 ? .malformed : .incomplete
        }
        guard let head = String(data: bytes[..<end.lowerBound], encoding: .utf8) else { return .malformed }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3 else { return .malformed }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .malformed }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        if headers["transfer-encoding"] != nil { return .malformed }
        var length = 0
        if let declared = headers["content-length"] {
            guard let value = Int(declared), value >= 0 else { return .malformed }
            length = value
        }
        if length > maxBody { return .tooLarge }
        let bodyStart = end.upperBound
        guard bytes.count - bodyStart >= length else { return .incomplete }
        return .request(HTTPRequest(
            method: String(requestLine[0]),
            target: String(requestLine[1]),
            headers: headers,
            body: Data(bytes[bodyStart..<bodyStart + length])
        ))
    }
}

/// A small HTTP endpoint on 127.0.0.1 for Claude Code's hooks and your own scripts.
/// The same rules as windows/listener.js.
///
///     POST /claude   a Claude Code hook event (its JSON as the body)
///     POST /fly      fly now; the body is {"message": "…"}, plain text, or empty for a random line
///     GET  /         "Sushi Buddy 1.4", to check it is listening
///
/// Only this computer can reach it. A web page could still try to post to it from the
/// browser, so any request carrying an Origin header (every browser sends one on a
/// cross-site POST) or a Host other than this address is refused.
@MainActor
final class Listener {
    nonisolated static let port: UInt16 = 7874
    nonisolated static let maxBody = 64 * 1024
    nonisolated static let maxMessage = 140

    enum Route: Equatable, Sendable { case hello, claude, fly }

    /// Which route a request may take, or the status it is refused with.
    nonisolated static func vet(method: String, target: String, headers: [String: String], port: UInt16) -> (status: Int, route: Route?) {
        if headers["origin"] != nil { return (403, nil) }
        let host = (headers["host"] ?? "").lowercased()
        guard host == "127.0.0.1:\(port)" || host == "localhost:\(port)" else { return (403, nil) }
        let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        switch (method, path) {
        case ("GET", "/"): return (200, .hello)
        case ("POST", "/claude"): return (204, .claude)
        case ("POST", "/fly"): return (204, .fly)
        default: return (404, nil)
        }
    }

    /// The message a /fly asks for, cleaned up, or nil for a random line.
    nonisolated static func flyMessage(_ body: Data) -> String? {
        var text = String(decoding: body, as: UTF8.self)
        if let parsed = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) {
            if let object = parsed as? [String: Any] {
                text = object["message"].map { ($0 as? String) ?? (($0 as? NSNumber)?.stringValue ?? "") } ?? ""
            } else if let string = parsed as? String {
                text = string
            } else if let number = parsed as? NSNumber {
                text = number.stringValue
            }
        }
        let spaced = String(String.UnicodeScalarView(text.unicodeScalars.map {
            $0.value < 0x20 || $0.value == 0x7F ? " " : $0
        }))
        let clean = spaced.trimmingCharacters(in: .whitespaces)
        let cut = String(String.UnicodeScalarView(clean.unicodeScalars.prefix(maxMessage)))
        return cut.isEmpty ? nil : cut
    }

    private var listener: NWListener?
    private let version: String
    private let onClaude: (ClaudeEvent) -> Void
    private let onFly: (String?) -> Void

    /// nil while listening or switched off; why it isn't listening otherwise.
    private(set) var problem: String?
    var onProblemChange: ((String?) -> Void)?

    init(version: String, onClaude: @escaping (ClaudeEvent) -> Void, onFly: @escaping (String?) -> Void) {
        self.version = version
        self.onClaude = onClaude
        self.onFly = onFly
    }

    func start() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Self.port) ?? .any)
        do {
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated { self?.listenerChanged(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            report("Couldn't listen on port \(Self.port): \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        report(nil)
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            logger.notice("listening on 127.0.0.1:\(Self.port)")
            report(nil)
        case .failed(let error):
            listener?.cancel()
            listener = nil
            if case .posix(.EADDRINUSE) = error {
                report("Port \(Self.port) is in use by another app.")
            } else {
                report("Couldn't listen on port \(Self.port): \(error.localizedDescription)")
            }
        default:
            break
        }
    }

    private func report(_ problem: String?) {
        self.problem = problem
        if let problem { logger.error("\(problem, privacy: .public)") }
        onProblemChange?(problem)
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
        // A client that connects and never finishes its request is dropped.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { connection.cancel() }
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                switch HTTPRequest.parse(buffer) {
                case .incomplete where error == nil && !isComplete:
                    self.receive(on: connection, buffer: buffer)
                case .incomplete, .malformed:
                    self.respond(on: connection, status: 400)
                case .tooLarge:
                    self.respond(on: connection, status: 413)
                case .request(let request):
                    self.serve(request, on: connection)
                }
            }
        }
    }

    private func serve(_ request: HTTPRequest, on connection: NWConnection) {
        let verdict = Self.vet(method: request.method, target: request.target, headers: request.headers, port: Self.port)
        switch verdict.route {
        case .hello:
            respond(on: connection, status: 200, body: "Sushi Buddy \(version)\n")
        case .claude:
            guard let event = try? JSONDecoder().decode(ClaudeEvent.self, from: request.body) else {
                respond(on: connection, status: 400)
                return
            }
            respond(on: connection, status: 204)
            onClaude(event)
        case .fly:
            respond(on: connection, status: 204)
            onFly(Self.flyMessage(request.body))
        case nil:
            respond(on: connection, status: verdict.status)
        }
    }

    private func respond(on connection: NWConnection, status: Int, body: String = "") {
        let reason = [200: "OK", 204: "No Content", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 413: "Content Too Large"]
        var head = "HTTP/1.1 \(status) \(reason[status] ?? "Error")\r\nConnection: close\r\n"
        if status != 204 {
            head += "Content-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\n"
        }
        let response = Data((head + "\r\n" + (status == 204 ? "" : body)).utf8)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}
