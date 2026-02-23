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
        pinLayerVisibleFromFirstFrame(box)
        overlay.addSublayer(box)

        let title = CATextLayer()
        title.string = request.test.testID ?? "Untitled Test"
        title.fontSize = 32
        title.foregroundColor = CGColor(gray: 1, alpha: 1)
        title.frame = CGRect(x: 36, y: renderSize.height - 86, width: renderSize.width * 0.42, height: 40)
        title.contentsScale = 2
        pinLayerVisibleFromFirstFrame(title)
        overlay.addSublayer(title)

        let adhesiveDisplayName = shortAdhesiveName(from: request.test.adhesive?.name)
        let subtitle = CATextLayer()
        subtitle.string = "\(request.test.product?.name ?? "Unknown Anchor") | \(adhesiveDisplayName)"
        subtitle.fontSize = 22
        subtitle.foregroundColor = CGColor(gray: 1, alpha: 0.95)
        subtitle.frame = CGRect(x: 36, y: renderSize.height - 122, width: renderSize.width * 0.42, height: 32)
        subtitle.contentsScale = 2
        pinLayerVisibleFromFirstFrame(subtitle)
        overlay.addSublayer(subtitle)

        if !request.forceSamples.isEmpty {
            let lbyToPrimaryOffset = request.syncConfiguration.effectiveOffsetSeconds
                + request.syncConfiguration.testerDataOffsetSeconds
            let trimIn = request.syncConfiguration.trimInSeconds ?? 0
            let trimOut = request.syncConfiguration.trimOutSeconds ?? max(trimIn, 0)
            let visibleEnd = max(trimOut, trimIn + 0.0001)
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
            let graphPoints = buildGraphPoints(
                samples: request.forceSamples,
                in: graphRect.size,
                lbyToPrimaryOffset: lbyToPrimaryOffset,
                visibleStartTime: trimIn,
                visibleEndTime: visibleEnd
            )
            graphLayer.path = buildGraphPath(points: graphPoints.map(\.point))
            overlay.addSublayer(graphLayer)

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

    private func shortAdhesiveName(from rawName: String?) -> String {
        guard let rawName, !rawName.isEmpty else { return "Unknown Adhesive" }
        let token = rawName.split(separator: "-", maxSplits: 1).first?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let token, !token.isEmpty {
            return token
        }
        return rawName
    }

    private func pinLayerVisibleFromFirstFrame(_ layer: CALayer) {
        layer.opacity = 1
        layer.beginTime = AVCoreAnimationBeginTimeAtZero
        layer.actions = [
            "opacity": NSNull(),
            "contents": NSNull(),
            "bounds": NSNull(),
            "position": NSNull()
        ]

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 1
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.duration = 0.0001
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "pinVisibleFromStart")
    }

    private func buildGraphPoints(
        samples: [ParsedForceSample],
        in size: CGSize,
        lbyToPrimaryOffset: Double,
        visibleStartTime: Double,
        visibleEndTime: Double
    ) -> [GraphPoint] {
        guard samples.count > 1 else { return [] }
        guard visibleEndTime > visibleStartTime else { return [] }

        let sorted = samples.sorted { $0.timeSeconds < $1.timeSeconds }
        let shifted: [(time: Double, force: Double)] = sorted.map {
            (time: $0.timeSeconds - lbyToPrimaryOffset, force: $0.forceLbs)
        }
        guard let first = shifted.first, let last = shifted.last else { return [] }

        let overlapStart = max(visibleStartTime, first.time)
        let overlapEnd = min(visibleEndTime, last.time)
        guard overlapEnd > overlapStart else { return [] }

        var clipped: [(time: Double, force: Double)] = [
            (time: overlapStart, force: interpolatedForce(at: overlapStart, in: shifted))
        ]
        clipped.append(contentsOf: shifted.filter { $0.time > overlapStart && $0.time < overlapEnd })
        clipped.append((time: overlapEnd, force: interpolatedForce(at: overlapEnd, in: shifted)))

        let minForce = clipped.map(\.force).min() ?? 0
        let maxForce = clipped.map(\.force).max() ?? 1
        let timeRange = max(visibleEndTime - visibleStartTime, 0.0001)
        let forceRange = max(maxForce - minForce, 0.0001)

        return clipped.map { sample in
            let x = ((sample.time - visibleStartTime) / timeRange) * size.width
            let y = ((sample.force - minForce) / forceRange) * size.height
            return GraphPoint(time: sample.time, point: CGPoint(x: x, y: y), force: sample.force)
        }
    }

    private func interpolatedForce(
        at time: Double,
        in samples: [(time: Double, force: Double)]
    ) -> Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        if time <= first.time { return first.force }
        if time >= last.time { return last.force }

        for index in 1..<samples.count {
            let left = samples[index - 1]
            let right = samples[index]
            if time <= right.time {
                let span = max(right.time - left.time, 0.000001)
                let t = (time - left.time) / span
                return left.force + (right.force - left.force) * t
            }
        }
        return last.force
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
