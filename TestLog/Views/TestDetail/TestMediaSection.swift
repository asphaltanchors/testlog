#if os(macOS)
import SwiftUI
import SwiftData

struct TestMediaSection: View {
    @Bindable var test: PullTest
    let onAttachFiles: () -> Void
    let onOpenWorkspace: () -> Void
    let onRemoveAsset: (Asset) -> Void
    @State private var assetPendingRemoval: Asset?
    @State private var showingAssetRemovalConfirmation = false

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
                            Text(creationTimestampText(for: asset))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
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
                            assetPendingRemoval = asset
                            showingAssetRemovalConfirmation = true
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
        .confirmationDialog(
            "Remove file from workspace?",
            isPresented: $showingAssetRemovalConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete File", role: .destructive) {
                confirmPendingAssetRemoval()
            }
            Button("Cancel", role: .cancel) {
                assetPendingRemoval = nil
                showingAssetRemovalConfirmation = false
            }
        } message: {
            Text("This will remove \(assetPendingRemoval?.filename ?? "this file") from the test and delete its managed copy from the app sandbox.")
        }
    }

    private func videoRoleText(for asset: Asset) -> String {
        (asset.videoRole ?? .unassigned).rawValue
    }

    private func creationTimestampText(for asset: Asset) -> String {
        if let filenameCreatedAt = Self.pixelFilenameTimestampUTC(for: asset.filename) {
            return "Created \(Self.assetTimestampFormatter.string(from: filenameCreatedAt))"
        }
        if let fileCreatedAt = fileCreatedAt(for: asset) {
            return "Created \(Self.assetTimestampFormatter.string(from: fileCreatedAt))"
        }
        return "Imported \(Self.assetTimestampFormatter.string(from: asset.createdAt))"
    }

    private func fileCreatedAt(for asset: Asset) -> Date? {
        guard let url = asset.resolvedURL else { return nil }
        let keys: Set<URLResourceKey> = [.creationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        return values.creationDate
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

    private func confirmPendingAssetRemoval() {
        guard let asset = assetPendingRemoval else { return }
        assetPendingRemoval = nil
        showingAssetRemovalConfirmation = false
        onRemoveAsset(asset)
    }
}

private extension TestMediaSection {
    static let assetTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    static let pixelFilenameTimestampRegex: NSRegularExpression = {
        let pattern = #"^PXL_(\d{8})_(\d{9})(?:\..*)?$"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    static let pixelFilenameTimestampParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmssSSS"
        return formatter
    }()

    static func pixelFilenameTimestampUTC(for filename: String) -> Date? {
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        guard let match = pixelFilenameTimestampRegex.firstMatch(in: filename, range: range),
              let dateRange = Range(match.range(at: 1), in: filename),
              let timeRange = Range(match.range(at: 2), in: filename) else {
            return nil
        }

        let utcStamp = "\(filename[dateRange])_\(filename[timeRange])"
        return pixelFilenameTimestampParser.date(from: utcStamp)
    }
}
#endif
