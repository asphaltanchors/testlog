#if os(macOS)
import SwiftUI

struct LBYForceGraphView: View {
    let samples: [ParsedForceSample]
    let cameraTimeSeconds: Double
    let lbySampleTimeSeconds: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LBY Force Graph")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let size = geo.size
                let timeRange = graphTimeRange
                let forceRange = graphForceRange

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.45))

                    if samples.count > 1 {
                        Path { path in
                            for (index, sample) in samples.enumerated() {
                                let point = CGPoint(
                                    x: xPosition(
                                        for: sample.timeSeconds,
                                        width: size.width,
                                        range: timeRange
                                    ),
                                    y: yPosition(
                                        for: sample.forceKN,
                                        height: size.height,
                                        range: forceRange
                                    )
                                )
                                if index == 0 {
                                    path.move(to: point)
                                } else {
                                    path.addLine(to: point)
                                }
                            }
                        }
                        .stroke(Color(red: 0.2, green: 0.85, blue: 0.95), lineWidth: 2)

                        verticalMarker(
                            x: xPosition(for: cameraTimeSeconds, width: size.width, range: timeRange),
                            color: .white.opacity(0.9),
                            height: size.height
                        )

                        verticalMarker(
                            x: xPosition(for: lbySampleTimeSeconds, width: size.width, range: timeRange),
                            color: .orange.opacity(0.95),
                            height: size.height
                        )
                    } else {
                        Text("No LBY data")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 140)

            HStack(spacing: 12) {
                legend(color: .white.opacity(0.9), label: "Camera Time")
                legend(color: .orange.opacity(0.95), label: "LBY Time (with Offset)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var graphTimeRange: ClosedRange<Double> {
        guard let first = samples.first, let last = samples.last else { return 0...1 }
        let upper = max(last.timeSeconds, first.timeSeconds + 1)
        return first.timeSeconds...upper
    }

    private var graphForceRange: ClosedRange<Double> {
        guard let minForce = samples.map(\.forceKN).min(), let maxForce = samples.map(\.forceKN).max() else {
            return 0...1
        }
        if abs(maxForce - minForce) < 0.0001 {
            return minForce...(minForce + 1)
        }
        return minForce...maxForce
    }

    private func xPosition(for time: Double, width: CGFloat, range: ClosedRange<Double>) -> CGFloat {
        let span = max(range.upperBound - range.lowerBound, 0.0001)
        let normalized = (time - range.lowerBound) / span
        let clamped = min(max(normalized, 0), 1)
        return CGFloat(clamped) * width
    }

    private func yPosition(for force: Double, height: CGFloat, range: ClosedRange<Double>) -> CGFloat {
        let span = max(range.upperBound - range.lowerBound, 0.0001)
        let normalized = (force - range.lowerBound) / span
        let clamped = min(max(normalized, 0), 1)
        return height - CGFloat(clamped) * height
    }

    @ViewBuilder
    private func verticalMarker(x: CGFloat, color: Color, height: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: height))
        }
        .stroke(color, lineWidth: 2)
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
        }
    }
}
#endif
