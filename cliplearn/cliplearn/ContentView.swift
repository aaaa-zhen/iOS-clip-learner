//
//  ContentView.swift
//  cliplearn
//
//  Created by meizu_mafuzhen on 5/29/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            StudyView(
                title: SampleEpisode.title,
                videoID: SampleEpisode.videoID,
                segments: SampleEpisode.segments
            )
        }
    }
}

#Preview {
    ContentView()
}
