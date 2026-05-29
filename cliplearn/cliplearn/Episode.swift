import Foundation

/// One episode the user generated on the Clip Learner web app. Mirrors the JSON
/// from `GET /api/episodes`. Unknown backend fields (video_path, user_id, …) are
/// simply ignored by Codable.
struct Episode: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let video_id: String?
    let title: String
    let url: String
    let thumbnail: String?
    let duration: Int?
    let status: String          // "ready" | "transcribing" | "error" | ...
    let created_at: String
    let studied_at: String?
    let pinned_at: String?
    var category: String?   // user-assigned, mutable in the feed
}

extension Episode {
    var isReady: Bool { status == "ready" }
    var isPinned: Bool { pinned_at != nil }

    /// Thumbnail to show on the card. Prefer the stored URL; otherwise derive it
    /// from the video id (works even when embedding is blocked).
    var thumbnailURL: URL? {
        if let thumbnail, !thumbnail.isEmpty, let url = URL(string: thumbnail) { return url }
        guard let video_id else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(video_id)/hqdefault.jpg")
    }

    /// "12:34" / "1:02:03" duration badge, or nil when unknown.
    var durationLabel: String? {
        guard let duration, duration > 0 else { return nil }
        let h = duration / 3600, m = (duration % 3600) / 60, s = duration % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// Human status label for the meta line (matches the web list).
    var statusLabel: String {
        switch status {
        case "ready": return "Ready"
        case "pending", "fetching_audio", "downloading": return "Fetching"
        case "transcribing": return "Transcribing"
        case "analyzing": return "Analyzing"
        case "error": return "Failed"
        default: return status.capitalized
        }
    }

    /// "2 weeks ago" style label derived from `created_at` ("yyyy-MM-dd HH:mm:ss", UTC).
    var createdAgoLabel: String {
        guard let date = Self.parser.date(from: created_at) else { return "" }
        return Self.relative.localizedString(for: date, relativeTo: Date())
    }

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let relative = RelativeDateTimeFormatter()
}
