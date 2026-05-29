import Foundation

/// Response of `GET /api/episodes/[id]` — everything the study view needs.
struct EpisodeDetail: Codable, Sendable {
    let episode: Episode
    let segments: [Segment]
    let annotations: [HumorAnnotation]
    let scenes: [SceneBreakdown]
    let vocabulary: [VocabEntry]
}

/// A server-analyzed humor/slang note anchored to a transcript segment.
struct HumorAnnotation: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let episode_id: String
    let segment_id: Int
    let category: String
    let explanation: String
    let excerpt: String
    let start_pos: Int
    let end_pos: Int
}

/// A multi-segment "scene" with a title and humor breakdown.
struct SceneBreakdown: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let episode_id: String
    let start_seg: Int
    let end_seg: Int
    let title: String
    let explanation: String
    let humor_types: [String]
}

/// Response of `POST /api/explain` for a word/phrase lookup.
struct ExplainResponse: Codable, Sendable {
    let definition: WordExplanation
}

/// A word/phrase explanation (mirrors the web `WordEntry`). All optional — the
/// free-dictionary path and the LLM path fill different subsets.
struct WordExplanation: Codable, Sendable {
    let phrase: String?
    let phonetic: String?
    let partOfSpeech: String?
    let definition: String?
    let example: String?
    let note: String?
}

/// A row from `GET /api/notebook` — a saved vocab word (or whole line), plus the
/// source episode's title/url that the backend joins in.
struct NotebookEntry: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let word: String
    let definition: String?
    let example: String?
    let phonetic: String?
    let category: String?
    let source_time: Double?
    let episode_id: String?
    let episode_title: String?
    let created_at: String?
}

/// A saved notebook word.
struct VocabEntry: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let word: String
    let definition: String
    let example: String
    let phonetic: String
    let source_text: String
    let episode_id: String?
    let source_time: Double?
    let category: String
    let confidence: Int
    let created_at: String
    let reviewed_at: String?
}
