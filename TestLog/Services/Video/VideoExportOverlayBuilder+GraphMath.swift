import CoreText
import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

extension VideoExportOverlayBuilder {
    func markerSamples(
        from points: [GraphPoint],
        startTime: Double,
        endTime: Double
    ) -> [GraphPoint] {
        var output: [GraphPoint] = []
        let startPoint = interpolatedPoint(at: startTime, in: points)
        output.append(
            GraphPoint(
                time: startTime,
                point: startPoint,
                force: interpolatedForce(at: startTime, in: points)
            )
        )
        output.append(contentsOf: points.filter { $0.time > startTime && $0.time < endTime })
        let endPoint = interpolatedPoint(at: endTime, in: points)
        output.append(
            GraphPoint(
                time: endTime,
                point: endPoint,
                force: interpolatedForce(at: endTime, in: points)
            )
        )

        var deduped: [GraphPoint] = []
        for sample in output.sorted(by: { $0.time < $1.time }) {
            if let last = deduped.last, abs(last.time - sample.time) < 0.000001 {
                deduped[deduped.count - 1] = sample
            } else {
                deduped.append(sample)
            }
        }
        return deduped
    }

    func interpolatedPoint(at time: Double, in points: [GraphPoint]) -> CGPoint {
        guard let first = points.first, let last = points.last else { return .zero }
        if time <= first.time { return first.point }
        if time >= last.time { return last.point }

        for index in 1..<points.count {
            let left = points[index - 1]
            let right = points[index]
            if time <= right.time {
                let span = max(right.time - left.time, 0.000001)
                let t = (time - left.time) / span
                return CGPoint(
                    x: left.point.x + (right.point.x - left.point.x) * t,
                    y: left.point.y + (right.point.y - left.point.y) * t
                )
            }
        }
        return last.point
    }

    func interpolatedForce(at time: Double, in points: [GraphPoint]) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if time <= first.time { return first.force }
        if time >= last.time { return last.force }

        for index in 1..<points.count {
            let left = points[index - 1]
            let right = points[index]
            if time <= right.time {
                let span = max(right.time - left.time, 0.000001)
                let t = (time - left.time) / span
                return left.force + (right.force - left.force) * t
            }
        }
        return last.force
    }

    func formattedForce(_ forceLbs: Double) -> String {
        String(format: "Force: %.2f lbf", forceLbs)
    }

    func pointValue(_ point: CGPoint) -> NSValue {
#if canImport(UIKit)
        return NSValue(cgPoint: point)
#else
        return NSValue(point: point)
#endif
    }

    func renderForceLabelImage(text: String, size: CGSize) -> CGImage? {
        let width = max(Int(size.width * 2), 1)
        let height = max(Int(size.height * 2), 1)
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        context.scaleBy(x: 2, y: 2)
        context.setFillColor(CGColor(gray: 1, alpha: 0.95))
        context.textMatrix = .identity

        let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, 16, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 0.95)
        ]
        let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 0, y: 4)
        CTLineDraw(line, context)

        return context.makeImage()
    }
}
