//
//  SessionListView.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//
//  Session detail view for editing session properties.
//  Session navigation is handled by the sidebar in ContentView.

import SwiftUI
import SwiftData

struct SessionDetailView: View {
    @Bindable var session: TestSession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Session Info") {
                DatePicker("Date", selection: $session.sessionDate, displayedComponents: .date)
                TextField("Weather Conditions", text: Binding(
                    get: { session.weatherConditions ?? "" },
                    set: { session.weatherConditions = $0.isEmpty ? nil : $0 }
                ))
                TextField("Notes", text: Binding(
                    get: { session.notes ?? "" },
                    set: { session.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(2...4)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete Session", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .confirmationDialog("Delete this session?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                modelContext.delete(session)
                dismiss()
            }
        } message: {
            Text("This will delete the session and all \(session.tests.count) associated tests.")
        }
    }
}
