#if os(macOS)
import SwiftUI
import SwiftData

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
                            Text("\(asset.assetType.rawValue) • \(videoRoleText(for: asset))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let bytes = asset.byteSize {
                                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if asset.assetType == .video {
                            Picker("Role", selection: videoRoleBinding(for: asset)) {
                                ForEach(VideoRole.allCases) { role in
                                    Text(role.rawValue).tag(role)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 160)
                        }
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

    private func videoRoleText(for asset: Asset) -> String {
        (asset.videoRole ?? .unassigned).rawValue
    }

    private func videoRoleBinding(for asset: Asset) -> Binding<VideoRole> {
        Binding(
            get: { asset.videoRole ?? .unassigned },
            set: { assignVideoRole($0, to: asset) }
        )
    }

    private func assignVideoRole(_ role: VideoRole, to asset: Asset) {
        guard asset.assetType == .video else { return }

        if role != .unassigned {
            for other in test.videoAssets where other.persistentModelID != asset.persistentModelID && other.videoRole == role {
                other.videoRole = .unassigned
                clearWorkspaceSelection(for: other, role: role)
            }
        }

        asset.videoRole = role
        applyWorkspaceSelection(for: asset, role: role)
    }

    private func clearWorkspaceSelection(for asset: Asset, role: VideoRole) {
        guard let config = test.videoSyncConfiguration else { return }
        if role == .anchorView, let selectedPrimary = config.primaryVideoAssetID, asset.matchesVideoSelectionID(selectedPrimary) {
            config.primaryVideoAssetID = nil
        }
        if role == .equipmentView, let selectedEquipment = config.equipmentVideoAssetID, asset.matchesVideoSelectionID(selectedEquipment) {
            config.equipmentVideoAssetID = nil
        }
    }

    private func applyWorkspaceSelection(for asset: Asset, role: VideoRole) {
        guard let config = test.videoSyncConfiguration else { return }
        switch role {
        case .anchorView:
            config.primaryVideoAssetID = asset.videoSelectionKey
            if let selectedEquipment = config.equipmentVideoAssetID, asset.matchesVideoSelectionID(selectedEquipment) {
                config.equipmentVideoAssetID = nil
            }
        case .equipmentView:
            config.equipmentVideoAssetID = asset.videoSelectionKey
            if let selectedPrimary = config.primaryVideoAssetID, asset.matchesVideoSelectionID(selectedPrimary) {
                config.primaryVideoAssetID = nil
            }
        case .unassigned:
            if let selectedPrimary = config.primaryVideoAssetID, asset.matchesVideoSelectionID(selectedPrimary) {
                config.primaryVideoAssetID = nil
            }
            if let selectedEquipment = config.equipmentVideoAssetID, asset.matchesVideoSelectionID(selectedEquipment) {
                config.equipmentVideoAssetID = nil
            }
        }
    }
}
#endif
