#if os(macOS)
import SwiftUI

struct TestImportReviewSheet: View {
    @Binding var pendingImportCandidates: [ImportedAssetCandidate]
    let isImportingCandidates: Bool
    let importStatusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Asset Import")
                .font(.title3.weight(.semibold))

            Group {
                if pendingImportCandidates.count > 3 {
                    ScrollView {
                        importCandidateCards
                    }
                    .frame(maxHeight: 240)
                } else {
                    importCandidateCards
                }
            }

            HStack {
                if isImportingCandidates {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                Text(importStatusMessage ?? "Ready to import \(pendingImportCandidates.count) file(s).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var importCandidateCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach($pendingImportCandidates) { $candidate in
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(candidate.sourceURL.lastPathComponent)
                            .font(.headline)

                        Picker("Type", selection: $candidate.selectedAssetType) {
                            Text(AssetType.video.rawValue).tag(AssetType.video)
                            Text(AssetType.testerData.rawValue).tag(AssetType.testerData)
                            Text(AssetType.document.rawValue).tag(AssetType.document)
                        }

                        if candidate.selectedAssetType == .video {
                            Picker("Video Role", selection: $candidate.selectedVideoRole) {
                                ForEach(VideoRole.allCases) { role in
                                    Text(role.rawValue).tag(role)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
#endif
