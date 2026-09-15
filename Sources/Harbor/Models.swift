import Foundation

struct Service: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var command: String
    var dir: String = ""
    var autoStart: Bool = false
    var autoRestart: Bool = false
    /// `/health`, or a whole URL. Empty means the port alone decides.
    var health: String = ""

    init(id: UUID = UUID(), name: String, command: String, dir: String = "",
         autoStart: Bool = false, autoRestart: Bool = false, health: String = "") {
        self.id = id
        self.name = name
        self.command = command
        self.dir = dir
        self.autoStart = autoStart
        self.autoRestart = autoRestart
        self.health = health
    }

    /// Decoded BY HAND: the synthesized decoder throws on a key that is missing
    /// even where there is a default, so a field added later would fail the whole
    /// array and silently empty every project's service list on upgrade.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "service"
        command = (try? c.decode(String.self, forKey: .command)) ?? ""
        dir = (try? c.decode(String.self, forKey: .dir)) ?? ""
        autoStart = (try? c.decode(Bool.self, forKey: .autoStart)) ?? false
        autoRestart = (try? c.decode(Bool.self, forKey: .autoRestart)) ?? false
        health = (try? c.decode(String.self, forKey: .health)) ?? ""
    }

    func resolvedCwd(projectPath: String) -> String {
        let trimmed = dir.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return projectPath }
        if trimmed.hasPrefix("/") { return trimmed }
        return (projectPath as NSString).appendingPathComponent(trimmed)
    }

    /// The URL to probe, once the port is known.
    func healthURL(port: Int?) -> URL? {
        let trimmed = health.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("http") { return URL(string: trimmed) }
        guard let port else { return nil }
        let path = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
        return URL(string: "http://127.0.0.1:\(port)\(path)")
    }
}

struct Project: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var path: String
    var tint: Int = 0
    var services: [Service] = []

    init(id: UUID = UUID(), name: String, path: String, tint: Int = 0, services: [Service] = []) {
        self.id = id
        self.name = name
        self.path = path
        self.tint = tint
        self.services = services
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "project"
        path = (try? c.decode(String.self, forKey: .path)) ?? ""
        tint = (try? c.decode(Int.self, forKey: .tint)) ?? 0
        services = (try? c.decode([Service].self, forKey: .services)) ?? []
    }

    /// Never `hashValue` — Swift seeds it per process, which would orphan every
    /// tmux session on the next launch.
    var shortID: String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 36).prefix(8).description
    }

    var badge: String {
        let words = name.split(whereSeparator: { " -_.".contains($0) })
        let letters = words.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    func session(for service: Service) -> String {
        "hb-\(shortID)-\(service.id.uuidString.prefix(8).lowercased())"
    }
}

enum ServiceStatus: Equatable {
    case stopped
    case starting
    case running
    case failed(Int?)

    var isLive: Bool { self == .running || self == .starting }
}

struct PortConflict: Equatable {
    let port: Int
    let pid: Int32
    let command: String
}
