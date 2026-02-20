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
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Product.self,
            PullTest.self,
            TestMeasurement.self,
            Location.self,
            Asset.self,
        ])
        let modelConfiguration = ModelConfiguration("TestLog", schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
