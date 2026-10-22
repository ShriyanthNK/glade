import Foundation

/// GLADE_HOME / GLADE_LEGACY_HOME override the locations (used by tests so they never touch the real install).
public let supportDir = ProcessInfo.processInfo.environment["GLADE_HOME"] ?? NSHomeDirectory() + "/.glade"
public let legacySupportDir = ProcessInfo.processInfo.environment["GLADE_LEGACY_HOME"] ?? NSHomeDirectory() + "/.claude-buddy"
public let socketPath = supportDir + "/glade.sock"

public struct Message {
    public var event = ""
    public var bundle = ""
    public var flags: [String: String] = [:]
    public var session: String?
    public var cwd: String?
    public var text: String?
    public init() {}
}

public struct Config: Equatable {
    public var chime = false
    public var waitDelay = 5.0
    public var doneDelay = 20.0
    public var giveUpAfter = 180.0      // seconds before Mochi leaves on his own; 0 = never
    public var snoozeUntil = 0.0        // epoch seconds
    public init() {}

    public static var path: String { supportDir + "/config.json" }

    public static func load(from path: String = Config.path) -> Config {
        var c = Config()
        guard let d = FileManager.default.contents(atPath: path),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return c }
        if let v = j["chime"] as? Bool { c.chime = v }
        if let v = j["waitDelay"] as? Double { c.waitDelay = v }
        if let v = j["doneDelay"] as? Double { c.doneDelay = v }
        if let v = j["giveUpAfter"] as? Double { c.giveUpAfter = v }
        if let v = j["snoozeUntil"] as? Double { c.snoozeUntil = v }
        return c
    }

    public func save(to path: String = Config.path) {
        let j: [String: Any] = ["chime": chime, "waitDelay": waitDelay, "doneDelay": doneDelay,
                                "giveUpAfter": giveUpAfter, "snoozeUntil": snoozeUntil]
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: j, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: URL(fileURLWithPath: path))
        }
    }

    /// Copies a claude-buddy config into the Glade support dir the first time Glade runs.
    /// Returns true when a copy was made. Never overwrites an existing Glade config.
    @discardableResult
    public static func migrateLegacy(from legacyPath: String = legacySupportDir + "/config.json",
                                     to newPath: String = Config.path) -> Bool {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: newPath), fm.fileExists(atPath: legacyPath) else { return false }
        Config.load(from: legacyPath).save(to: newPath)
        return true
    }
}

/// Wire format: event \n bundle-id \n k=v flags \n one-line JSON \n
public func parseMessage(_ raw: String) -> Message {
    let lines = raw.split(separator: "\n", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
    var m = Message()
    m.event = lines.count > 0 ? lines[0].trimmingCharacters(in: .whitespaces) : ""
    m.bundle = lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespaces) : ""
    if lines.count > 2 {
        for kv in lines[2].split(separator: " ") {
            let p = kv.split(separator: "=", maxSplits: 1).map(String.init)
            if p.count == 2 { m.flags[p[0]] = p[1] }
        }
    }
    if lines.count > 3, let d = lines[3].data(using: .utf8),
       let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
        m.session = j["session_id"] as? String
        m.cwd = j["cwd"] as? String
        m.text = j["message"] as? String
    }
    return m
}

private func makeAddr() -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(socketPath.utf8CString)
    withUnsafeMutablePointer(to: &addr.sun_path) {
        $0.withMemoryRebound(to: CChar.self, capacity: 104) { dst in
            for (i, b) in bytes.prefix(103).enumerated() { dst[i] = b }
        }
    }
    return addr
}

private func connectSocket() -> Int32? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    if fd < 0 { return nil }
    var addr = makeAddr()
    let ok = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    if ok != 0 { close(fd); return nil }
    return fd
}

public func daemonRunning() -> Bool {
    guard let fd = connectSocket() else { return false }
    close(fd)
    return true
}

public func sendRaw(_ text: String) -> Bool {
    guard let fd = connectSocket() else { return false }
    defer { close(fd) }
    let bytes = Array(text.utf8)
    return write(fd, bytes, bytes.count) == bytes.count
}

public final class Server {
    var fd: Int32 = -1
    public init() {}

    public func start(_ handler: @escaping (Message) -> Void) -> Bool {
        try? FileManager.default.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        unlink(socketPath)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = makeAddr()
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 16) == 0 else { return false }
        chmod(socketPath, 0o600)
        let listenFd = fd
        Thread.detachNewThread {
            while true {
                let c = accept(listenFd, nil, nil)
                if c < 0 { continue }
                var tv = timeval(tv_sec: 1, tv_usec: 0)
                setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                var data = Data()
                var buf = [UInt8](repeating: 0, count: 8192)
                while data.count < 1_000_000 {
                    let n = read(c, &buf, buf.count)
                    if n <= 0 { break }
                    data.append(buf, count: n)
                    if data.filter({ $0 == 10 }).count >= 4 { break }
                }
                close(c)
                if let s = String(data: data, encoding: .utf8), !s.isEmpty {
                    let m = parseMessage(s)
                    DispatchQueue.main.async { handler(m) }
                }
            }
        }
        return true
    }

    public func stop() { close(fd); unlink(socketPath) }
}
