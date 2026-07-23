import Foundation

struct SyncState: Codable, Sendable {
    var activeScoreID: UUID?
    var activeBlockID: UUID?
    var activeSlideID: UUID?
    var scores: [StudioScore]?
    var pulses: [StudentPulse]?
    var constitution: CourseConstitution?
}

struct APIClient: Sendable {
    struct Health: Decodable, Sendable {
        struct ProviderStatus: Decodable, Sendable {
            let keyLoaded: Bool
            let textModel: String?
            let imageModel: String?
            let imageGeneration: Bool
        }
        let ok: Bool
        let ai: Bool
        let activeProvider: String?
        let primaryProvider: String?
        let fallbackOrder: [String]?
        let providers: [String: ProviderStatus]?
    }
    enum ClientError: LocalizedError {
        case server(String)
        var errorDescription: String? {
            switch self { case .server(let message): return message }
        }
    }
    struct GeneratedSlide: Decodable, Sendable {
        let title: String
        let body: String
        let notes: String
    }
    let baseURL: URL
    var token: String?

    func health() async throws -> Health {
        var request = URLRequest(url: baseURL.appendingPathComponent("/health"))
        request.timeoutInterval = 3
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            if let payload = try? JSONDecoder().decode([String: String].self, from: data),
               let message = payload["error"] {
                throw ClientError.server(message)
            }
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Health.self, from: data)
    }

    func signIn(name: String, email: String, role: AccountRole) async throws -> Account {
        try await request("/auth/demo", body: ["name": name, "email": email, "role": role.rawValue])
    }

    func chat(prompt: String, score: StudioScore?) async throws -> String {
        struct Body: Encodable { let prompt: String; let score: StudioScore? }
        struct Reply: Decodable { let text: String }
        let reply: Reply = try await request("/ai/respond", body: Body(prompt: prompt, score: score))
        return reply.text
    }

    func generateImage(prompt: String) async throws -> URL {
        struct Reply: Decodable { let url: URL }
        let reply: Reply = try await request("/ai/image", body: ["prompt": prompt])
        return reply.url
    }

    func generateSlides(prompt: String, score: StudioScore?) async throws -> [GeneratedSlide] {
        struct Body: Encodable { let prompt: String; let score: StudioScore? }
        struct Reply: Decodable { let slides: [GeneratedSlide] }
        let reply: Reply = try await request("/ai/slides", body: Body(prompt: prompt, score: score))
        return reply.slides
    }

    func getSync() async throws -> SyncState {
        var request = URLRequest(url: baseURL.appendingPathComponent("/score/sync"))
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            if let payload = try? JSONDecoder().decode([String: String].self, from: data),
               let message = payload["error"] {
                throw ClientError.server(message)
            }
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SyncState.self, from: data)
    }

    func postSync(activeScoreID: UUID?, activeBlockID: UUID?, activeSlideID: UUID?, scores: [StudioScore]?, pulses: [StudentPulse]?, constitution: CourseConstitution?) async throws -> SyncState {
        struct Body: Encodable {
            let activeScoreID: UUID?
            let activeBlockID: UUID?
            let activeSlideID: UUID?
            let scores: [StudioScore]?
            let pulses: [StudentPulse]?
            let constitution: CourseConstitution?
        }
        return try await request("/score/sync", body: Body(activeScoreID: activeScoreID, activeBlockID: activeBlockID, activeSlideID: activeSlideID, scores: scores, pulses: pulses, constitution: constitution))
    }

    private func request<Input: Encodable, Output: Decodable>(_ path: String, body: Input) async throws -> Output {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            if let payload = try? JSONDecoder().decode([String: String].self, from: data),
               let message = payload["error"] {
                throw ClientError.server(message)
            }
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Output.self, from: data)
    }
}
