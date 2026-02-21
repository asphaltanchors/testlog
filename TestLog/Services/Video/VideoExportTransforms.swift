import AVFoundation
import CoreGraphics
import Foundation

enum VideoExportContentMode {
    case fill
    case fit
    case fitLeading
}

enum VideoExportTransforms {
    static func placedTransform(
        for track: AVAssetTrack,
        destination: CGRect,
        contentMode: VideoExportContentMode,
        extraQuarterTurnsClockwise: Int = 0,
        cropRectNormalized: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    ) async throws -> CGAffineTransform {
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let sourceRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let orientedSize = CGSize(width: abs(sourceRect.width), height: abs(sourceRect.height))
        guard orientedSize.width > 0, orientedSize.height > 0 else { return .identity }

        let normalizedOrientation = transform.concatenating(
            CGAffineTransform(translationX: -sourceRect.minX, y: -sourceRect.minY)
        )

        let (quarterTurnTransform, rotatedSize) = clockwiseQuarterTurnTransform(
            turns: extraQuarterTurnsClockwise,
            sourceSize: orientedSize
        )
        let croppedRect = absoluteCropRect(
            normalized: cropRectNormalized,
            in: CGRect(origin: .zero, size: rotatedSize)
        )

        guard croppedRect.width > 0, croppedRect.height > 0 else { return .identity }

        let scale: CGFloat
        switch contentMode {
        case .fill:
            scale = max(destination.width / croppedRect.width, destination.height / croppedRect.height)
        case .fit, .fitLeading:
            scale = min(destination.width / croppedRect.width, destination.height / croppedRect.height)
        }
        let scaled = CGSize(width: croppedRect.width * scale, height: croppedRect.height * scale)
        let tx: CGFloat
        let ty: CGFloat
        switch contentMode {
        case .fitLeading:
            tx = destination.minX
            ty = destination.minY + (destination.height - scaled.height) / 2
        case .fill, .fit:
            tx = destination.minX + (destination.width - scaled.width) / 2
            ty = destination.minY + (destination.height - scaled.height) / 2
        }

        return normalizedOrientation
            .concatenating(quarterTurnTransform)
            .concatenating(CGAffineTransform(translationX: -croppedRect.minX, y: -croppedRect.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: tx, y: ty))
    }

    static func clockwiseQuarterTurnTransform(
        turns: Int,
        sourceSize: CGSize
    ) -> (CGAffineTransform, CGSize) {
        let normalizedTurns = ((turns % 4) + 4) % 4
        switch normalizedTurns {
        case 1:
            return (
                CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: sourceSize.height, ty: 0),
                CGSize(width: sourceSize.height, height: sourceSize.width)
            )
        case 2:
            return (
                CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: sourceSize.width, ty: sourceSize.height),
                sourceSize
            )
        case 3:
            return (
                CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: sourceSize.width),
                CGSize(width: sourceSize.height, height: sourceSize.width)
            )
        default:
            return (.identity, sourceSize)
        }
    }

    static func absoluteCropRect(normalized: CGRect, in bounds: CGRect) -> CGRect {
        let clamped = normalizedCrop(normalized)
        return CGRect(
            x: bounds.minX + clamped.minX * bounds.width,
            y: bounds.minY + clamped.minY * bounds.height,
            width: bounds.width * clamped.width,
            height: bounds.height * clamped.height
        )
    }

    static func normalizedCrop(_ rect: CGRect) -> CGRect {
        rect.clampedNormalized(minSize: 0.05)
    }
}
