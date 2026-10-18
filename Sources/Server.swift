import Foundation

let supportDir = NSHomeDirectory() + "/.claude-buddy"
let socketPath = supportDir + "/buddy.sock"

struct Message {
    var event = ""
    var bundle = ""
    var flags: [String: String] = [:]
    var session: String?
    var cwd: String?
    var text: String?
}

struct Config {
    var chime = false
    var waitDelay = 5.0
    var doneDelay = 20.0
    var giveUpAfter = 180.0      // seconds before Mochi leaves on his own; 0 = never
    var snoozeUntil = 0.0        // epoch seconds

    static var path: String { supportDir + "/config.json" }

    static func load() -> Config {
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

    func save() {
        let j: [String: Any] = ["chime": chime, "waitDelay": waitDelay, "doneDelay": doneDelay,
                                "giveUpAfter": giveUpAfter, "snoozeUntil": snoozeUntil]
        try? FileManager.default.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: j, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: URL(fileURLWithPath: Config.path))
        }
    }
}

/// Wire format: event \n bundle-id \n k=v flags \n one-line JSON \n
func parseMessage(_ raw: String) -> Message {
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

func daemonRunning() -> Bool {
    guard let fd = connectSocket() else { return false }
    close(fd)
    return true
}

func sendRaw(_ text: String) -> Bool {
    guard let fd = connectSocket() else { return false }
    defer { close(fd) }
    let bytes = Array(text.utf8)
    return write(fd, bytes, bytes.count) == bytes.count
}

final class Server {
    var fd: Int32 = -1

    func start(_ handler: @escaping (Message) -> Void) -> Bool {
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

    func stop() { close(fd); unlink(socketPath) }
}
