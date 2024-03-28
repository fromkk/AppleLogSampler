//
//  ContentView.swift
//  AppleLogSampler
//
//  Created by Kazuya Ueoka on 2024/03/28.
//

import ComposableArchitecture
import SwiftUI

struct ContentView: View {
    var body: some View {
        CameraView(store: Store(initialState: CameraFeature.State(), reducer: {
            CameraFeature()
                ._printChanges()
        }))
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
