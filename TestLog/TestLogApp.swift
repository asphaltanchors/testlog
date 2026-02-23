//
//  TestLogApp.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

@main
struct TestLogApp: App {
    var sharedModelContainer: ModelContainer = TestLogContainer.create()
#if os(macOS)
    private let csvImportService = TestCSVImportService()
#endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
#if os(macOS)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import Tests from CSV…") {
                    importTestsFromCSV()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }
#endif

#if os(macOS)
        Settings {
            AppPreferencesView()
                .modelContainer(sharedModelContainer)
        }
#endif
    }
}

#if os(macOS)
private extension TestLogApp {
    func importTestsFromCSV() {
        let panel = NSOpenPanel()
        panel.title = "Import Tests from CSV"
        panel.message = "Select the CSV export from your Google Sheet."
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let startedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if startedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let report = try csvImportService.importCSV(from: url, into: sharedModelContainer.mainContext)
            showImportAlert(title: "CSV Import Complete", message: report.summary, style: .informational)
        } catch {
            showImportAlert(
                title: "CSV Import Failed",
                message: error.localizedDescription,
                style: .critical
            )
        }
    }

    func showImportAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
#endif
