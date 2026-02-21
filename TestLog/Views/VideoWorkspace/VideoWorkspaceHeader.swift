#if os(macOS)
import SwiftUI

struct VideoWorkspaceHeader: View {
    let testID: String?
    let usesImmersiveStyle: Bool
    let canExport: Bool
    let isExportingVideo: Bool
    let onExport: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(testID ?? "Test")
                    .font(.title3.weight(.semibold))
                Text("Trim first, then align, then export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                Button {
                    onExport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(isExportingVideo || !canExport)

                Button("Done") {
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .opacity(usesImmersiveStyle ? 0 : 1)
        }
    }
}
#endif
