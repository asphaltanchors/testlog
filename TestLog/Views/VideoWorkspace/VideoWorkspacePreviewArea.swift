#if os(macOS)
import AVKit
import SwiftUI

struct VideoWorkspacePreviewArea: View {
    @Bindable var coordinator: VideoWorkspaceCoordinator
    let primaryAsset: Asset?
    let equipmentAsset: Asset?

    var body: some View {
        if primaryAsset != nil {
            HStack(spacing: 12) {
                WorkspaceVideoPreview(
                    player: coordinator.primaryPlayer,
                    videoSize: coordinator.videoDisplaySize(for: primaryAsset),
                    rotationQuarterTurns: 0,
                    cropRectNormalized: .constant(CGRect(x: 0, y: 0, width: 1, height: 1)),
                    isEditingCrop: .constant(false),
                    showEditingTools: false
                )
                if let equipmentAsset {
                    WorkspaceVideoPreview(
                        player: coordinator.equipmentPlayer,
                        videoSize: coordinator.videoDisplaySize(for: equipmentAsset),
                        rotationQuarterTurns: coordinator.equipmentRotationQuarterTurns,
                        cropRectNormalized: Binding(
                            get: { coordinator.equipmentCropRectNormalized },
                            set: { coordinator.setEquipmentCropRectNormalized($0) }
                        ),
                        isEditingCrop: $coordinator.isEditingEquipmentFrame,
                        showEditingTools: true,
                        onRotateClockwise: {
                            coordinator.rotateEquipmentClockwise()
                        },
                        onResetCrop: {
                            coordinator.resetEquipmentCrop()
                        }
                    )
                }
            }
        } else {
            ContentUnavailableView(
                "No Videos Attached",
                systemImage: "video.slash",
                description: Text("Attach at least one video before using the workspace.")
            )
        }
    }
}

struct WorkspaceVideoPreview: View {
    let player: AVPlayer
    let videoSize: CGSize
    let rotationQuarterTurns: Int
    @Binding var cropRectNormalized: CGRect
    @Binding var isEditingCrop: Bool
    let showEditingTools: Bool
    var onRotateClockwise: (() -> Void)? = nil
    var onResetCrop: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let containerSize = geo.size
            let fullVideoRect = aspectFitRect(
                for: orientedVideoSize,
                in: CGRect(origin: .zero, size: containerSize)
            )
            let cropRect = cropRectInView(fullVideoRect: fullVideoRect)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.95))

                if isEditingCrop {
                    OrientedWorkspacePlayer(player: player, quarterTurns: rotationQuarterTurns)
                        .frame(width: fullVideoRect.width, height: fullVideoRect.height)
                        .position(x: fullVideoRect.midX, y: fullVideoRect.midY)

                    CropEditingOverlay(
                        fullVideoRect: fullVideoRect,
                        cropRect: cropRect,
                        onCropChanged: { newCrop in
                            cropRectNormalized = normalizedRect(newCrop, in: fullVideoRect)
                        }
                    )
                } else {
                    let mapped = mappedVideoRect(fullVideoRect: fullVideoRect, cropRect: cropRect)
                    OrientedWorkspacePlayer(player: player, quarterTurns: rotationQuarterTurns)
                        .frame(width: mapped.width, height: mapped.height)
                        .position(x: mapped.midX, y: mapped.midY)
                }

                if showEditingTools {
                    HStack(spacing: 8) {
                        Button(isEditingCrop ? "Done Crop" : "Edit Crop") {
                            isEditingCrop.toggle()
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            onRotateClockwise?()
                        } label: {
                            Label("Rotate 90°", systemImage: "rotate.right")
                        }
                        .buttonStyle(.bordered)

                        Button("Reset") {
                            onResetCrop?()
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var normalizedRotation: Int {
        let mod = rotationQuarterTurns % 4
        return mod < 0 ? mod + 4 : mod
    }

    private var orientedVideoSize: CGSize {
        guard videoSize.width > 0, videoSize.height > 0 else {
            return CGSize(width: 16, height: 9)
        }
        if normalizedRotation.isMultiple(of: 2) {
            return videoSize
        }
        return CGSize(width: videoSize.height, height: videoSize.width)
    }

    private func cropRectInView(fullVideoRect: CGRect) -> CGRect {
        let normalized = cropRectNormalized.standardized.clampedNormalized(minSize: 0.05)
        return CGRect(
            x: fullVideoRect.minX + normalized.minX * fullVideoRect.width,
            y: fullVideoRect.minY + normalized.minY * fullVideoRect.height,
            width: fullVideoRect.width * normalized.width,
            height: fullVideoRect.height * normalized.height
        )
    }

    private func normalizedRect(_ rect: CGRect, in fullVideoRect: CGRect) -> CGRect {
        guard fullVideoRect.width > 0, fullVideoRect.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let x = (rect.minX - fullVideoRect.minX) / fullVideoRect.width
        let y = (rect.minY - fullVideoRect.minY) / fullVideoRect.height
        let w = rect.width / fullVideoRect.width
        let h = rect.height / fullVideoRect.height
        return CGRect(x: x, y: y, width: w, height: h).clampedNormalized(minSize: 0.05)
    }

    private func mappedVideoRect(fullVideoRect: CGRect, cropRect: CGRect) -> CGRect {
        let safeCrop = cropRect.standardized
        guard safeCrop.width > 0, safeCrop.height > 0 else { return fullVideoRect }
        let scale = min(fullVideoRect.width / safeCrop.width, fullVideoRect.height / safeCrop.height)
        let targetSize = CGSize(width: safeCrop.width * scale, height: safeCrop.height * scale)
        let targetOrigin = CGPoint(
            x: fullVideoRect.midX - targetSize.width / 2,
            y: fullVideoRect.midY - targetSize.height / 2
        )
        return CGRect(
            x: targetOrigin.x - (safeCrop.minX - fullVideoRect.minX) * scale,
            y: targetOrigin.y - (safeCrop.minY - fullVideoRect.minY) * scale,
            width: fullVideoRect.width * scale,
            height: fullVideoRect.height * scale
        )
    }

    private func aspectFitRect(for sourceSize: CGSize, in bounds: CGRect) -> CGRect {
        guard
            sourceSize.width > 0,
            sourceSize.height > 0,
            bounds.width > 0,
            bounds.height > 0
        else {
            return bounds
        }
        let scale = min(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
        let fitted = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: bounds.midX - fitted.width / 2,
            y: bounds.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}

struct OrientedWorkspacePlayer: View {
    let player: AVPlayer
    let quarterTurns: Int

    var body: some View {
        GeometryReader { geo in
            let turns = normalizedTurns
            let targetSize = geo.size
            let baseSize = turns.isMultiple(of: 2)
                ? targetSize
                : CGSize(width: targetSize.height, height: targetSize.width)

            WorkspacePlayerView(player: player)
                .frame(width: baseSize.width, height: baseSize.height)
                .rotationEffect(.degrees(Double(turns) * 90))
                .position(x: targetSize.width / 2, y: targetSize.height / 2)
        }
        .clipped()
    }

    private var normalizedTurns: Int {
        let mod = quarterTurns % 4
        return mod < 0 ? mod + 4 : mod
    }
}
#endif
