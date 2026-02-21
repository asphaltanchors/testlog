import AVFoundation
import CoreText
import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

struct VideoExportOverlayBuilder {
    struct GraphPoint {
        let time: Double
        let point: CGPoint
        let force: Double
    }

    func buildOverlayLayer(request: VideoExportRequest, renderSize: CGSize) -> CALayer {
        let overlay = CALayer()
        overlay.frame = CGRect(origin: .zero, size: renderSize)

        let leftMargin: CGFloat = 24
        let box = CALayer()
        box.backgroundColor = CGColor(gray: 0, alpha: 0.5)
        box.cornerRadius = 10
        let infoBoxFrame = CGRect(
            x: leftMargin,
            y: renderSize.height - 140,
            width: renderSize.width * 0.45,
            height: 110
        )
        box.frame = infoBoxFrame
        overlay.addSublayer(box)

        let title = CATextLayer()
        title.string = request.test.testID ?? "Untitled Test"
        title.fontSize = 26
        title.foregroundColor = CGColor(gray: 1, alpha: 1)
        title.frame = CGRect(x: 36, y: renderSize.height - 80, width: renderSize.width * 0.4, height: 36)
        title.contentsScale = 2
        overlay.addSublayer(title)

        let subtitle = CATextLayer()
        subtitle.string = "\(request.test.product?.name ?? "Unknown Anchor") | \(request.test.adhesive?.name ?? "Unknown Adhesive")"
        subtitle.fontSize = 18
        subtitle.foregroundColor = CGColor(gray: 1, alpha: 0.95)
        subtitle.frame = CGRect(x: 36, y: renderSize.height - 110, width: renderSize.width * 0.4, height: 30)
        subtitle.contentsScale = 2
        overlay.addSublayer(subtitle)

        if !request.forceSamples.isEmpty {
            let graphHeight: CGFloat = 150
            let graphRect = CGRect(
                x: renderSize.width * 0.52,
                y: infoBoxFrame.maxY - graphHeight,
                width: renderSize.width * 0.44,
                height: graphHeight
            )
            let graphBackground = CALayer()
            graphBackground.frame = graphRect
            graphBackground.backgroundColor = CGColor(gray: 0, alpha: 0.45)
            graphBackground.cornerRadius = 8
            overlay.addSublayer(graphBackground)

            let graphLayer = CAShapeLayer()
            graphLayer.frame = graphRect
            graphLayer.strokeColor = CGColor(red: 0.2, green: 0.85, blue: 0.95, alpha: 1.0)
            graphLayer.fillColor = nil
            graphLayer.lineWidth = 2
            let graphPoints = buildGraphPoints(samples: request.forceSamples, in: graphRect.size)
            graphLayer.path = buildGraphPath(points: graphPoints.map(\.point))
            overlay.addSublayer(graphLayer)

            let trimIn = request.syncConfiguration.trimInSeconds ?? 0
            let trimOut = request.syncConfiguration.trimOutSeconds ?? max(trimIn, 0)
            let animatedSamples = markerSamples(
                from: graphPoints,
                startTime: max(trimIn, graphPoints.first?.time ?? trimIn),
                endTime: min(max(trimOut, trimIn + 0.0001), graphPoints.last?.time ?? trimOut)
            )

            if let markerLayer = buildGraphMarkerLayer(animatedSamples: animatedSamples) {
                graphLayer.addSublayer(markerLayer)
            }

            if let forceLabel = buildCurrentForceLabelLayer(
                animatedSamples: animatedSamples,
                trimIn: trimIn,
                trimOut: trimOut
            ) {
                graphLayer.addSublayer(forceLabel)
            }
        }

        return overlay
    }

    private func buildGraphPoints(samples: [ParsedForceSample], in size: CGSize) -> [GraphPoint] {
        guard samples.count > 1 else { return [] }

        let sorted = samples.sorted { $0.timeSeconds < $1.timeSeconds }
        let minTime = sorted.first?.timeSeconds ?? 0
        let maxTime = sorted.last?.timeSeconds ?? 1
        let minForce = sorted.map(\.forceLbs).min() ?? 0
        let maxForce = sorted.map(\.forceLbs).max() ?? 1
        let timeRange = max(maxTime - minTime, 0.0001)
        let forceRange = max(maxForce - minForce, 0.0001)

        return sorted.map { sample in
            let x = ((sample.timeSeconds - minTime) / timeRange) * size.width
            let y = ((sample.forceLbs - minForce) / forceRange) * size.height
            return GraphPoint(time: sample.timeSeconds, point: CGPoint(x: x, y: y), force: sample.forceLbs)
        }
    }

    private func buildGraphPath(points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard points.count > 1 else { return path }
        for (index, point) in points.enumerated() {
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    private func buildGraphMarkerLayer(animatedSamples: [GraphPoint]) -> CALayer? {
        guard let first = animatedSamples.first else { return nil }

        let marker = CAShapeLayer()
        marker.path = CGPath(ellipseIn: CGRect(x: -4, y: -4, width: 8, height: 8), transform: nil)
        marker.fillColor = CGColor(red: 1, green: 0.35, blue: 0.25, alpha: 1)
        marker.strokeColor = CGColor(gray: 1, alpha: 0.9)
        marker.lineWidth = 1
        marker.position = first.point

        let start = first.time
        let end = animatedSamples.last?.time ?? first.time
        let duration = max(end - start, 0.0001)
        let animation = CAKeyframeAnimation(keyPath: "position")
        animation.values = animatedSamples.map { pointValue($0.point) }
        animation.keyTimes = animatedSamples.map { NSNumber(value: ($0.time - start) / duration) }
        animation.duration = duration
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.calculationMode = .linear
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        marker.add(animation, forKey: "graphMarkerPosition")

        return marker
    }

    private func buildCurrentForceLabelLayer(
        animatedSamples: [GraphPoint],
        trimIn: Double,
        trimOut: Double
    ) -> CALayer? {
        guard let first = animatedSamples.first else { return nil }
        let duration = max(trimOut - trimIn, 0.0001)
        let labelFrame = CGRect(x: 12, y: 6, width: 240, height: 24)
        let label = CALayer()
        label.contentsScale = 2
        label.frame = labelFrame
        label.contentsGravity = .resize

        let initialText = formattedForce(first.force)
        guard let initialImage = renderForceLabelImage(text: initialText, size: labelFrame.size) else {
            return nil
        }
        label.contents = initialImage

        let keyTimes = animatedSamples.map {
            NSNumber(value: min(max(($0.time - trimIn) / duration, 0), 1))
        }
        let frames: [CGImage] = animatedSamples.compactMap { sample in
            renderForceLabelImage(text: formattedForce(sample.force), size: labelFrame.size)
        }
        guard frames.count == keyTimes.count, !frames.isEmpty else { return label }

        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.keyTimes = keyTimes
        animation.duration = duration
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.calculationMode = .discrete
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        label.add(animation, forKey: "forceValueText")

        return label
    }

}
