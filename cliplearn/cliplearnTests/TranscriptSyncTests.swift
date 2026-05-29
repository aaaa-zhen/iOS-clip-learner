import Testing
@testable import cliplearn

private func seg(_ i: Int, _ start: Double, _ end: Double) -> Segment {
    Segment(id: i, episode_id: "ep", index_num: i, start_time: start, end_time: end, text: "line \(i)")
}

// Three lines with a gap between line 1 (4.0–8.0) and line 2 (10.0–14.0).
private let segments = [seg(0, 0.0, 4.0), seg(1, 4.0, 8.0), seg(2, 10.0, 14.0)]

@Test func highlightsSegmentContainingTime() {
    #expect(TranscriptSync.currentSegmentIndex(at: 2.0, in: segments) == 0)
    #expect(TranscriptSync.currentSegmentIndex(at: 5.0, in: segments) == 1)
    #expect(TranscriptSync.currentSegmentIndex(at: 12.0, in: segments) == 2)
}

@Test func boundaryIsInclusiveOfStart() {
    #expect(TranscriptSync.currentSegmentIndex(at: 4.0, in: segments) == 1)
    #expect(TranscriptSync.currentSegmentIndex(at: 0.0, in: segments) == 0)
}

@Test func beforeFirstSegmentHighlightsNothing() {
    #expect(TranscriptSync.currentSegmentIndex(at: -1.0, in: segments) == nil)
}

@Test func inGapKeepsPreviousSegmentHighlighted() {
    // 9.0 is after line 1 ends (8.0) but before line 2 starts (10.0).
    #expect(TranscriptSync.currentSegmentIndex(at: 9.0, in: segments) == 1)
}

@Test func afterLastSegmentHighlightsLast() {
    #expect(TranscriptSync.currentSegmentIndex(at: 999.0, in: segments) == 2)
}

@Test func emptySegmentsHighlightsNothing() {
    #expect(TranscriptSync.currentSegmentIndex(at: 5.0, in: []) == nil)
}
