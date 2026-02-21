//
//  TestLogApp.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//

import SwiftUI
import SwiftData

@main
struct TestLogApp: App {
    var sharedModelContainer: ModelContainer = TestLogContainer.create()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
