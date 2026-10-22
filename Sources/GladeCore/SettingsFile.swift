import Foundation

public enum HookError: Error, Equatable, CustomStringConvertible {
    case unreadable(String)      // settings.json exists but is not a JSON object

    public var description: String {
        switch self {
        case .unreadable(let why): return "settings.json is not valid JSON (\(why)); fix it first, nothing was changed"
        }
    }
}

/// Reads and writes Claude Code's settings.json. Every write saves a timestamped backup next to the file first
/// and replaces the file atomically; anything we don't understand is passed through untouched.
struct SettingsFile {
    let path: String

    func load() throws -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: path) else { return [:] }
        if data.allSatisfy({ $0 == 32 || $0 == 10 || $0 == 13 || $0 == 9 }) { return [:] }
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HookError.unreadable("top level is not an object")
            }
            return obj
        } catch let e as HookError { throw e }
        catch { throw HookError.unreadable(error.localizedDescription) }
    }

    /// Returns the backup path, or nil when there was no file to back up.
    func write(_ root: [String: Any]) throws -> String? {
        let fm = FileManager.default
        var backup: String?
        if fm.fileExists(atPath: path) {
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; f.locale = Locale(identifier: "en_US_POSIX")
            let b = path + ".glade-backup." + f.string(from: Date())
            try? fm.removeItem(atPath: b)
            try fm.copyItem(atPath: path, toPath: b)
            backup = b
        }
        try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let tmp = path + ".glade-tmp"
        try data.write(to: URL(fileURLWithPath: tmp))
        if fm.fileExists(atPath: path) {
            _ = try fm.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: tmp))
        } else {
            try fm.moveItem(atPath: tmp, toPath: path)
        }
        return backup
    }
}
