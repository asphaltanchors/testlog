#if os(macOS)
import SwiftUI

struct VideoWorkspaceControls: View {
    @Bindable var coordinator: VideoWorkspaceCoordinator
    let videoAssets: [Asset]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            roleSelectors
            alignmentControls
            actionRow
        }
    }

    private var roleSelectors: some View {
        VStack(spacing: 8) {
            Picker(
                "Primary Video",
                selection: Binding(
                    get: { coordinator.primarySelectionID },
                    set: { coordinator.setPrimarySelectionID($0) }
                )
            ) {
                Text("Select").tag("")
                ForEach(videoAssets, id: \.persistentModelID) { asset in
                    Text(asset.filename).tag(coordinator.assetIdentifier(asset))
                }
            }

            Picker(
                "Equipment Video",
                selection: Binding(
                    get: { coordinator.equipmentSelectionID },
                    set: { coordinator.setEquipmentSelectionID($0) }
                )
            ) {
                Text("None").tag("")
                ForEach(videoAssets, id: \.persistentModelID) { asset in
                    Text(asset.filename).tag(coordinator.assetIdentifier(asset))
                }
            }
        }
    }

    private var alignmentControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alignment")
                .font(.headline)

            HStack {
                Text("Auto Offset")
                Spacer()
                Text(coordinator.autoOffsetText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Manual Camera Offset")
                Spacer()
                TextField(
                    "Seconds",
                    value: Binding(
                        get: { coordinator.manualOffsetSeconds },
                        set: { coordinator.setManualOffsetSeconds($0) }
                    ),
                    format: .number.precision(.fractionLength(3))
                )
                .frame(width: 120)
                .multilineTextAlignment(.trailing)
            }

            Divider()

            HStack {
                Text("LBY Force (kN)")
                Spacer()
                Text(coordinator.currentTesterForceText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("LBY Offset")
                Spacer()
                TextField(
                    "Seconds",
                    value: Binding(
                        get: { coordinator.testerDataOffsetSeconds },
                        set: { coordinator.setTesterDataOffsetSeconds($0) }
                    ),
                    format: .number.precision(.fractionLength(3))
                )
                .frame(width: 120)
                .multilineTextAlignment(.trailing)
            }

            if let testerStatus = coordinator.testerDataStatusMessage {
                Text(testerStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LBYForceGraphView(
                samples: coordinator.testerDataSamples,
                cameraTimeSeconds: coordinator.equipmentPreviewTimeSeconds,
                lbySampleTimeSeconds: coordinator.lbySampleTimeSeconds
            )
        }
    }

    private var actionRow: some View {
        HStack {
            Button("Auto Sync") {
                Task { await coordinator.runAutoSync() }
            }
            .disabled(coordinator.isRunningAutoSync || videoAssets.count < 2)

            if coordinator.isRunningAutoSync {
                ProgressView()
                    .scaleEffect(0.7)
            }

            Spacer()
        }
        .overlay(alignment: .bottomLeading) {
            if let statusMessage = coordinator.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 18)
            }
        }
    }
}
#endif
