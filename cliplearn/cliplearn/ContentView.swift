//
//  ContentView.swift
//  cliplearn
//
//  Created by meizu_mafuzhen on 5/29/26.
//

import SwiftUI

struct ContentView: View {
    @State private var auth = AuthStore()

    var body: some View {
        RootView(auth: auth)
            .task { await auth.bootstrap() }
            .sheet(isPresented: $auth.showLogin) {
                AuthView(auth: auth)
                    .presentationDetents([.height(460)])
                    .presentationDragIndicator(.visible)
            }
    }
}

#Preview {
    ContentView()
}
