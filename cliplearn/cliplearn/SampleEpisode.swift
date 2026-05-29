import Foundation

/// Hardcoded sample data for the v1 "get the video working" milestone — no
/// backend or login needed. Once the JSON API is wired up, this is replaced by
/// data fetched from `GET /api/episodes/[id]`.
///
/// Uses the first-ever YouTube video ("Me at the zoo"), which is guaranteed to
/// allow embedding. Swap `videoID` + `segments` for one of your real Taskmaster
/// clips + its transcript to test with actual content.
enum SampleEpisode {
    static let title = "Me at the zoo"
    static let videoID = "jNQXAC9IVRw"

    static let segments: [Segment] = [
        Segment(id: 0, episode_id: "sample", index_num: 0, start_time: 0.0, end_time: 5.0,
                text: "All right, so here we are in front of the elephants."),
        Segment(id: 1, episode_id: "sample", index_num: 1, start_time: 5.0, end_time: 11.0,
                text: "The cool thing about these guys is that they have really, really, really long trunks."),
        Segment(id: 2, episode_id: "sample", index_num: 2, start_time: 11.0, end_time: 14.0,
                text: "And that's cool."),
        Segment(id: 3, episode_id: "sample", index_num: 3, start_time: 14.0, end_time: 19.0,
                text: "And that's pretty much all there is to say.")
    ]
}
