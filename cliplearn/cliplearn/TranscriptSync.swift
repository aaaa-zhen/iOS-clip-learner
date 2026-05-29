import Foundation

enum TranscriptSync {
    /// The index of the transcript line to highlight at `time` (seconds): the last
    /// segment whose `start_time` is at or before `time`. Returns `nil` when `time`
    /// precedes the first segment or there are no segments. Lines stay highlighted
    /// through gaps until the next line starts, which avoids flicker.
    ///
    /// Assumes `segments` are sorted ascending by `start_time` (the backend orders
    /// them by `index_num`).
    static func currentSegmentIndex(at time: Double, in segments: [Segment]) -> Int? {
        var result: Int?
        for (i, segment) in segments.enumerated() {
            if segment.start_time <= time {
                result = i
            } else {
                break
            }
        }
        return result
    }
}
