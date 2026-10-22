import CoreGraphics
import Foundation

/// A backdrop the terminal can sit in front of.
public struct Look: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// Drifting fireflies are part of the Night Forest; photos get none by default.
    public var fireflies: Bool
    public var builtin: Bool

    public init(id: String, name: String, fireflies: Bool, builtin: Bool) {
        self.id = id; self.name = name; self.fireflies = fireflies; self.builtin = builtin
    }
}

/// Built-in looks ship inside the app; the user's own live in `~/.glade/looks/<id>/{backdrop.png, look.json}`.
public struct LookStore {
    public static let builtins = [Look(id: "night-forest", name: "Night Forest", fireflies: true, builtin: true)]
    public static let defaultId = "night-forest"

    public let userDir: String
    public let builtinDir: String

    public init(userDir: String = supportDir + "/looks", builtinDir: String = LookStore.defaultBuiltinDir()) {
        self.userDir = userDir
        self.builtinDir = builtinDir
    }

    /// GLADE_RESOURCES, else the app bundle's Resources/Looks, else the repo's Resources/Looks (swift run / tests).
    public static func defaultBuiltinDir() -> String {
        if let e = ProcessInfo.processInfo.environment["GLADE_RESOURCES"] { return e }
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Looks").path, FileManager.default.fileExists(atPath: r) { return r }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Looks").path
    }

    public func backdropURL(_ look: Look) -> URL {
        look.builtin ? URL(fileURLWithPath: builtinDir + "/" + look.id + ".png")
                     : URL(fileURLWithPath: userDir + "/" + look.id + "/backdrop.png")
    }

    /// Built-ins first, then the user's looks oldest first. Unreadable or half-written folders are skipped.
    public func all() -> [Look] {
        let fm = FileManager.default
        var mine: [(Look, Date)] = []
        for name in ((try? fm.contentsOfDirectory(atPath: userDir)) ?? []).sorted() {
            let dir = userDir + "/" + name
            guard let data = fm.contents(atPath: dir + "/look.json"),
                  let look = try? JSONDecoder().decode(Look.self, from: data),
                  look.id == name, !look.builtin,
                  fm.fileExists(atPath: dir + "/backdrop.png") else { continue }
            let made = (try? fm.attributesOfItem(atPath: dir + "/look.json")[.creationDate] as? Date) ?? Date.distantPast
            mine.append((look, made ?? .distantPast))
        }
        return Self.builtins + mine.sorted { $0.1 < $1.1 }.map { $0.0 }
    }

    /// The look with this id, or the default one if it was deleted.
    public func look(id: String) -> Look {
        let all = self.all()
        return all.first { $0.id == id } ?? all[0]
    }

    @discardableResult
    public func add(processed image: CGImage, name: String, fireflies: Bool = false) throws -> Look {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let look = Look(id: "user-" + UUID().uuidString.prefix(8).lowercased(),
                        name: clean.isEmpty ? "My look" : String(clean.prefix(40)), fireflies: fireflies, builtin: false)
        let dir = userDir + "/" + look.id
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        do {
            try LookPipeline.writePNG(image, to: URL(fileURLWithPath: dir + "/backdrop.png"))
            try JSONEncoder().encode(look).write(to: URL(fileURLWithPath: dir + "/look.json"))   // last: marks it complete
        } catch {
            try? FileManager.default.removeItem(atPath: dir)
            throw error
        }
        return look
    }

    @discardableResult
    public func add(photo: URL, name: String, options: LookPipeline.Options = .init()) throws -> Look {
        guard let src = LookPipeline.load(photo) else {
            throw NSError(domain: "Glade", code: 3, userInfo: [NSLocalizedDescriptionKey: "Couldn't read \(photo.lastPathComponent) as an image"])
        }
        return try add(processed: LookPipeline.process(src, options: options).image, name: name)
    }

    /// Deletes a user look. Built-ins are never removed.
    public func remove(_ id: String) throws {
        guard !Self.builtins.contains(where: { $0.id == id }), id.hasPrefix("user-") else { return }
        try FileManager.default.removeItem(atPath: userDir + "/" + id)
    }
}
