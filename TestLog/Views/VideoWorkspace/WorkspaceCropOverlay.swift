#if os(macOS)
import SwiftUI

struct CropEditingOverlay: View {
    let fullVideoRect: CGRect
    let cropRect: CGRect
    let onCropChanged: (CGRect) -> Void

    @State private var dragStartPoint: CGPoint?
    private let minimumCropPixels: CGFloat = 20

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(fullVideoRect)
                path.addRect(cropRect)
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))

            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange, lineWidth: 2)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let point = clampPointToVideo(value.location)
                    if dragStartPoint == nil {
                        dragStartPoint = point
                    }
                    guard let start = dragStartPoint else { return }
                    let rect = rectFromPoints(start, point).ensuringMinimumSize(
                        minWidth: minimumCropPixels,
                        minHeight: minimumCropPixels,
                        inside: fullVideoRect
                    )
                    onCropChanged(rect)
                }
                .onEnded { _ in
                    dragStartPoint = nil
                }
        )
    }

    private func clampPointToVideo(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, fullVideoRect.minX), fullVideoRect.maxX),
            y: min(max(point.y, fullVideoRect.minY), fullVideoRect.maxY)
        )
    }

    private func rectFromPoints(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }
}
#endif
