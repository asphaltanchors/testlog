import CoreGraphics

extension CGRect {
    func clampedNormalized(minSize: CGFloat) -> CGRect {
        let normalizedMin = min(max(minSize, 0), 1)
        var rect = self.standardized
        rect.origin.x = rect.origin.x.isFinite ? rect.origin.x : 0
        rect.origin.y = rect.origin.y.isFinite ? rect.origin.y : 0
        rect.size.width = rect.size.width.isFinite ? rect.size.width : 1
        rect.size.height = rect.size.height.isFinite ? rect.size.height : 1

        rect.origin.x = min(max(rect.origin.x, 0), 1)
        rect.origin.y = min(max(rect.origin.y, 0), 1)
        rect.size.width = min(max(rect.size.width, normalizedMin), 1)
        rect.size.height = min(max(rect.size.height, normalizedMin), 1)

        if rect.maxX > 1 {
            rect.origin.x = max(0, 1 - rect.width)
        }
        if rect.maxY > 1 {
            rect.origin.y = max(0, 1 - rect.height)
        }
        return rect
    }

    func ensuringMinimumSize(minWidth: CGFloat, minHeight: CGFloat, inside bounds: CGRect) -> CGRect {
        var rect = self.standardized
        rect.size.width = max(rect.width, minWidth)
        rect.size.height = max(rect.height, minHeight)

        if rect.maxX > bounds.maxX {
            rect.origin.x = bounds.maxX - rect.width
        }
        if rect.maxY > bounds.maxY {
            rect.origin.y = bounds.maxY - rect.height
        }
        if rect.minX < bounds.minX {
            rect.origin.x = bounds.minX
        }
        if rect.minY < bounds.minY {
            rect.origin.y = bounds.minY
        }

        rect.size.width = min(rect.width, bounds.width)
        rect.size.height = min(rect.height, bounds.height)
        return rect
    }
}
