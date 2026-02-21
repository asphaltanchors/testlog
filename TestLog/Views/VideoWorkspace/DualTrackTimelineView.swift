#if os(macOS)
import SwiftUI

struct DualTrackTimelineView: View {
    let domain: ClosedRange<Double>
    let primaryRange: ClosedRange<Double>
    let secondaryRange: ClosedRange<Double>
    @Binding var trimIn: Double
    @Binding var trimOut: Double
    @Binding var playhead: Double
    let onScrubBegan: () -> Void
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void

    private let horizontalPadding: CGFloat = 12
    private let barHeight: CGFloat = 28
    private let primaryY: CGFloat = 20
    private let equipmentY: CGFloat = 56
    private let tracksTopY: CGFloat = 14
    private let tracksBottomY: CGFloat = 92
    private let playheadBottomY: CGFloat = 104

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width - horizontalPadding * 2, 1)
            let trimMinGap = max((domain.upperBound - domain.lowerBound) * 0.0025, 0.01)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(height: tracksBottomY - tracksTopY)
                    .offset(x: horizontalPadding, y: tracksTopY)

                trackBar(title: "Primary", range: primaryRange, color: .blue, y: primaryY, width: width)
                trackBar(
                    title: "Equipment",
                    range: secondaryRange,
                    color: .green,
                    y: equipmentY,
                    width: width
                )

                let trimInX = xPosition(for: trimIn, width: width)
                let trimOutX = xPosition(for: trimOut, width: width)
                let playheadX = xPosition(for: playhead, width: width)

                verticalMarker(x: trimInX, color: .orange)
                verticalMarker(x: trimOutX, color: .orange)
                verticalMarker(x: playheadX, color: .white.opacity(0.95))

                bracketHandle(x: trimInX, y: tracksTopY - 2, isLeftBracket: true)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let candidate = time(for: value.location.x, width: width)
                                trimIn = min(max(primaryRange.lowerBound, candidate), trimOut - trimMinGap)
                            }
                    )

                bracketHandle(x: trimOutX, y: tracksTopY - 2, isLeftBracket: false)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let candidate = time(for: value.location.x, width: width)
                                trimOut = max(min(primaryRange.upperBound, candidate), trimIn + trimMinGap)
                            }
                    )

                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .position(x: playheadX, y: playheadBottomY)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                onScrubBegan()
                                let candidate = time(for: value.location.x, width: width)
                                let clamped = min(max(candidate, trimIn), trimOut)
                                playhead = clamped
                                onScrubChanged(clamped)
                            }
                            .onEnded { value in
                                let candidate = time(for: value.location.x, width: width)
                                let clamped = min(max(candidate, trimIn), trimOut)
                                playhead = clamped
                                onScrubEnded(clamped)
                            }
                    )
            }
            .overlay(alignment: .bottomTrailing) {
                Text(
                    String(
                        format: "Trim %.2fs - %.2fs | Playhead %.2fs",
                        trimIn,
                        trimOut,
                        playhead
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.trailing, horizontalPadding)
                .padding(.bottom, 2)
            }
        }
    }

    private func trackBar(
        title: String,
        range: ClosedRange<Double>,
        color: Color,
        y: CGFloat,
        width: CGFloat
    ) -> some View {
        let startX = xPosition(for: range.lowerBound, width: width)
        let endX = xPosition(for: range.upperBound, width: width)
        let barWidth = max(endX - startX, 2)

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.88))
                .frame(width: barWidth, height: barHeight)
                .offset(x: startX, y: y)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .offset(x: startX + 8, y: y + 6)
        }
    }

    private func bracketHandle(x: CGFloat, y: CGFloat, isLeftBracket: Bool) -> some View {
        Text(isLeftBracket ? "[" : "]")
            .font(.system(size: 18, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
            .position(x: x, y: y)
    }

    private func verticalMarker(x: CGFloat, color: Color) -> some View {
        Path { path in
            path.move(to: CGPoint(x: x, y: tracksTopY))
            path.addLine(to: CGPoint(x: x, y: tracksBottomY))
        }
        .stroke(color, lineWidth: 2)
    }

    private func xPosition(for time: Double, width: CGFloat) -> CGFloat {
        let denominator = max(domain.upperBound - domain.lowerBound, 0.0001)
        let normalized = (time - domain.lowerBound) / denominator
        return horizontalPadding + CGFloat(normalized) * width
    }

    private func time(for x: CGFloat, width: CGFloat) -> Double {
        let normalized = Double((x - horizontalPadding) / width)
        let clamped = min(max(normalized, 0), 1)
        return domain.lowerBound + clamped * (domain.upperBound - domain.lowerBound)
    }
}
#endif
