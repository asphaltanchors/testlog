#if os(macOS)
import SwiftUI

struct TestMediaSection: View {
    @Bindable var test: PullTest
    let onAttachFiles: () -> Void
    let onOpenWorkspace: () -> Void
    let onRemoveAsset: (Asset) -> Void

    var body: some View {
        Section("Media") {
            Button("Attach Files") {
                onAttachFiles()
            }

            Button("Open Video Workspace") {
                onOpenWorkspace()
            }
            .disabled(test.videoAssets.isEmpty)

            if !test.assets.isEmpty {
                ForEach(test.assets.sorted(by: { $0.createdAt > $1.createdAt }), id: \.persistentModelID) { asset in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(asset.filename)
                                .font(.headline)
                            Text("\(asset.assetType.rawValue) • \(asset.videoRole?.rawValue ?? "—")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let bytes = asset.byteSize {
                                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Remove", role: .destructive) {
                            onRemoveAsset(asset)
                        }
                    }
                }
            } else {
                Text("No media assets attached.")
                    .foregroundStyle(.secondary)
            }

            if let issue = test.validationIssues.first {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            Text(
                test.videoAssets.isEmpty
                    ? "Attach at least one video to open the workspace."
                    : "Open Video Workspace to trim, align, and export."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
#endif
