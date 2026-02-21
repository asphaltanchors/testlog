#if os(macOS)
import AppKit
import SwiftUI

struct VideoWorkspaceExportSheet: View {
    let exportModalState: ExportModalState?
    let isExportingVideo: Bool
    let onClose: () -> Void
    let onDone: () -> Void

    var body: some View {
        switch exportModalState {
        case .exporting(let filename):
            VStack(alignment: .leading, spacing: 14) {
                Text("Exporting Video")
                    .font(.title3.weight(.semibold))
                Text("Rendering \(filename). This can take a minute depending on video length.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ProgressView()
                    .controlSize(.regular)
                HStack {
                    Spacer()
                    Button("Working...") {}
                        .disabled(true)
                }
            }

        case .completed(let outputURL):
            VStack(alignment: .leading, spacing: 14) {
                Text("Export Complete")
                    .font(.title3.weight(.semibold))
                Text(outputURL.lastPathComponent)
                    .font(.body.monospaced())
                Text("Your composed video is ready. You can reveal it in Finder or finish and return to the test detail view.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                    }
                    Spacer()
                    Button("Done") {
                        onDone()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 14) {
                Text("Export Failed")
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Close") {
                        onClose()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }

        case nil:
            EmptyView()
        }
    }
}
#endif
