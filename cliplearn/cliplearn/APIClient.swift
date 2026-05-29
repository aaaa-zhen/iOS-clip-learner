import Foundation

/// Where the backend lives. Local dev server for now; flip to `.production`
/// once the VPS serves the iOS JSON endpoints over HTTPS.
enum APIConfig {
    /// iOS Simulator shares the Mac's network, so localhost reaches `npm run dev`.
    static let localDev = URL(string: "http://localhost:5174")!
    /// The hosted VPS. Plain HTTP for now — the backend sets the session cookie
    /// `secure:false` so it DOES persist over HTTP (login is verified working).
    /// The remaining concern is cleartext transport: move to HTTPS (domain +
    /// Let's Encrypt), then revert the cookie to `secure:!dev` and drop the ATS
    /// exceptions in Info.plist.
    static let production = URL(string: "http://43.134.87.27")!

    static let baseURL = production
}

enum APIError: LocalizedError {
    case unauthorized
    case rateLimited
    case server(status: Int, message: String?)
    case decoding(Error)
    case network(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Your session expired. Please log in again."
        case .rateLimited: return "Too many requests — slow down a moment."
        case .server(_, let message): return message ?? "The server returned an error."
        case .decoding: return "Couldn't read the server's response."
        case .network(let error): return error.localizedDescription
        case .invalidResponse: return "Unexpected response from the server."
        }
    }
}

/// One typed wrapper over `URLSession`. Relies on the session's shared cookie
/// storage to persist `clip_session` across launches and re-send it automatically.
final class APIClient: Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(baseURL: URL = APIConfig.baseURL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: Episodes

    func episodes() async throws -> [Episode] {
        try await get("/api/episodes")
    }

    /// Delete an episode (and its segments/annotations/vocab) via the existing
    /// `DELETE /api/process` endpoint.
    func deleteEpisode(id: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/process"))
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["id": id])
        _ = try await send(request)
    }

    /// Set (or clear, with nil) an episode's category via `PATCH /api/episodes/[id]`.
    func setCategory(episodeID: String, category: String?) async throws {
        let encoded = episodeID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? episodeID
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/episodes/\(encoded)"))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["category": category ?? ""])
        _ = try await send(request)
    }

    /// Submit a YouTube/X URL to generate a new episode (kicks off the server
    /// download → transcribe → analyze pipeline). Returns immediately; poll the
    /// episode list for status.
    func addEpisode(url: String) async throws {
        _ = try await post("/api/process", body: ["url": url])
    }

    func episodeDetail(id: String) async throws -> EpisodeDetail {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await get("/api/episodes/\(encoded)")
    }

    /// Drop the stored session cookie (used on sign-out).
    func clearStoredCookies() {
        guard let storage = session.configuration.httpCookieStorage else { return }
        storage.cookies?.forEach(storage.deleteCookie)
    }

    // MARK: Word lookup

    func explain(word: String, currentLine: String, episodeTitle: String) async throws -> WordExplanation {
        let body: [String: Any] = [
            "word": word,
            "context": [
                "currentLine": currentLine,
                "episodeTitle": episodeTitle,
                "source": "transcript"
            ]
        ]
        let data = try await post("/api/explain", body: body)
        let response: ExplainResponse = try decode(data)
        return response.definition
    }

    // MARK: Notebook

    func notebook() async throws -> [NotebookEntry] {
        try await get("/api/notebook")
    }

    func deleteNotebookEntry(id: Int) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/notebook"))
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["id": id])
        _ = try await send(request)
    }

    /// Save a single looked-up word/phrase with its explanation. Throws
    /// `APIError.server(409, …)` if already saved (caller treats as success).
    func saveWord(word: String, definition: String?, example: String?, phonetic: String?,
                  sourceText: String, episodeID: String, sourceTime: Double, category: String?) async throws {
        let body: [String: Any] = [
            "word": word,
            "definition": definition ?? "",
            "example": example ?? "",
            "phonetic": phonetic ?? "",
            "source_text": sourceText,
            "episode_id": episodeID,
            "source_time": sourceTime,
            "category": (category?.isEmpty == false) ? category! : "general"
        ]
        _ = try await post("/api/notebook", body: body)
    }

    /// Save a whole transcript line as a note. Throws `APIError.server(409, …)`
    /// if it's already saved (the caller can treat that as success).
    func saveLine(_ line: String, episodeID: String, sourceTime: Double) async throws {
        let body: [String: Any] = [
            "word": line,
            "definition": "",
            "example": "",
            "phonetic": "",
            "source_text": line,
            "episode_id": episodeID,
            "source_time": sourceTime,
            "category": "sentence"
        ]
        _ = try await post("/api/notebook", body: body)
    }

    // MARK: Auth

    func login(username: String, password: String) async throws {
        try await auth(action: "login", username: username, password: password)
    }

    func signup(username: String, password: String) async throws {
        try await auth(action: "signup", username: username, password: password)
    }

    private func auth(action: String, username: String, password: String) async throws {
        let body = ["action": action, "username": username, "password": password]
        _ = try await post("/api/auth", body: body)
    }

    // MARK: Core

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        return try decode(try await send(request))
    }

    @discardableResult
    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    /// Performs the request, mapping transport + HTTP status into `APIError`.
    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited
        default:
            throw APIError.server(status: http.statusCode, message: Self.errorMessage(from: data))
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    /// Pulls `{ "error": "…" }` out of a non-2xx body when present.
    private static func errorMessage(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj["error"] as? String
    }
}
