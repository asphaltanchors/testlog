#if os(macOS)
import SwiftUI

struct VideoWorkspaceTimeline: View {
    @Bindable var coordinator: VideoWorkspaceCoordinator

    var body: some View {
        DualTrackTimelineView(
            domain: coordinator.timelineDomain,
            primaryRange: coordinator.primaryRange,
            secondaryRange: coordinator.secondaryRange,
            trimIn: Binding(
                get: { coordinator.trimIn },
                set: { coordinator.setTrimIn($0) }
            ),
            trimOut: Binding(
                get: { coordinator.trimOut },
                set: { coordinator.setTrimOut($0) }
            ),
            playhead: Binding(
                get: { coordinator.scrubberTimeSeconds },
                set: { coordinator.setPlayhead($0) }
            ),
            onScrubBegan: {
                coordinator.scrubBegan()
            },
            onScrubChanged: { time in
                coordinator.scrubChanged(time)
            },
            onScrubEnded: { time in
                coordinator.scrubEnded(time)
            }
        )
        .disabled(!coordinator.hasPrimaryVideo)
    }
}
#endif
