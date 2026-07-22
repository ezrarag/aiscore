import Foundation

struct PersistenceService: Sendable {
    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Score", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let fileURL = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder.score.decode(type, from: data)
        } catch {
            print("⚠️ Persistence load warning for \(name): \(error.localizedDescription). Preserving corrupted file backup.")
            let backupURL = directory.appendingPathComponent("\(name).corrupted")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.moveItem(at: fileURL, to: backupURL)
            return nil
        }
    }

    func save<T: Encodable & Sendable>(_ value: T, to name: String) {
        let targetURL = directory.appendingPathComponent(name)
        DispatchQueue.global(qos: .utility).async {
            guard let data = try? JSONEncoder.score.encode(value) else { return }
            try? data.write(to: targetURL, options: .atomic)
        }
    }

    func remove(_ name: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
}

private extension JSONEncoder {
    static var score: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e }
}
private extension JSONDecoder {
    static var score: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
