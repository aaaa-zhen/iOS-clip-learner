import Foundation

/// A single transcript line for an episode. Mirrors the backend `Segment` shape
/// (`src/lib/types.ts` in the clip-learner web app).
struct Segment: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let episode_id: String
    let index_num: Int
    let start_time: Double
    let end_time: Double
    let text: String
}
