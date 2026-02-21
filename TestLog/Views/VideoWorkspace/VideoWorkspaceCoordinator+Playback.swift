#if os(macOS)
import AVFoundation
import Foundation

extension VideoWorkspaceCoordinator {
    var normalizedTrimIn: Double {
        min(max(syncConfiguration?.trimInSeconds ?? 0, 0), primaryDuration)
    }

    var normalizedTrimOut: Double {
        let lower = normalizedTrimIn
        let rawOut = syncConfiguration?.trimOutSeconds ?? primaryDuration
        return min(max(rawOut, lower), primaryDuration)
    }

    var sharedTimelineBounds: ClosedRange<Double> {
        normalizedTrimIn...normalizedTrimOut
    }

    func boundedSharedTime(_ value: Double) -> Double {
        min(max(value, sharedTimelineBounds.lowerBound), sharedTimelineBounds.upperBound)
    }

    func seekPlayersToTrimStart() {
        let trimIn = normalizedTrimIn
        scrubberTimeSeconds = boundedSharedTime(trimIn)
        seekPlayers(toPrimaryTime: trimIn)
    }

    func reloadPlayers() {
        pauseSyncedPlayback()

        if let primaryURL = primaryVideoAsset?.resolvedURL {
            primaryPlayer.replaceCurrentItem(with: AVPlayerItem(url: primaryURL))
        } else {
            primaryPlayer.replaceCurrentItem(with: nil)
        }

        if let equipmentURL = equipmentVideoAsset?.resolvedURL {
            equipmentPlayer.replaceCurrentItem(with: AVPlayerItem(url: equipmentURL))
        } else {
            equipmentPlayer.replaceCurrentItem(with: nil)
        }

        primaryPlayer.isMuted = false
        equipmentPlayer.isMuted = true
        seekPlayersToTrimStart()
    }

    func playSyncedFromCurrentTime() {
        seekPlayers(toPrimaryTime: scrubberTimeSeconds)
        if primaryPlayer.currentItem != nil {
            primaryPlayer.play()
        }
        if equipmentVideoAsset != nil, equipmentPlayer.currentItem != nil {
            equipmentPlayer.play()
        }
        isPlayingSynced = true
    }

    func pauseSyncedPlayback() {
        primaryPlayer.pause()
        equipmentPlayer.pause()
        isPlayingSynced = false
    }

    func seekPlayers(toPrimaryTime primaryTime: Double) {
        let boundedPrimary = boundedSharedTime(primaryTime)
        let primaryClamped = clampedTime(boundedPrimary, for: primaryPlayer)
        seek(player: primaryPlayer, to: primaryClamped)

        let secondaryRequested = max(0, boundedPrimary + (syncConfiguration?.effectiveOffsetSeconds ?? 0))
        let secondaryClamped = clampedTime(secondaryRequested, for: equipmentPlayer)
        seek(player: equipmentPlayer, to: secondaryClamped)
        scrubberTimeSeconds = boundedPrimary
    }

    func seekPlayersDuringScrub(toPrimaryTime primaryTime: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastScrubSeekUptime < 0.04 { return }
        lastScrubSeekUptime = now
        seekPlayers(toPrimaryTime: primaryTime)
    }

    func installPrimaryTimeObserver() {
        removePrimaryTimeObserver()
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        primaryTimeObserverToken = primaryPlayer.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                let seconds = time.seconds
                guard seconds.isFinite, !self.isScrubbing else { return }
                self.scrubberTimeSeconds = self.boundedSharedTime(seconds)

                if self.isPlayingSynced && seconds >= self.sharedTimelineBounds.upperBound {
                    self.pauseSyncedPlayback()
                }
            }
        }
    }

    func removePrimaryTimeObserver() {
        if let token = primaryTimeObserverToken {
            primaryPlayer.removeTimeObserver(token)
            primaryTimeObserverToken = nil
        }
    }

    func clampedTime(_ requested: Double, for player: AVPlayer) -> Double {
        let nonNegative = max(0, requested)
        guard let item = player.currentItem else { return nonNegative }
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0 else { return nonNegative }
        return min(nonNegative, max(duration - 0.001, 0))
    }

    func seek(player: AVPlayer, to seconds: Double) {
        guard let item = player.currentItem else { return }
        if item.status == .failed { return }
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(
            to: time,
            toleranceBefore: CMTime(value: 1, timescale: 60),
            toleranceAfter: CMTime(value: 1, timescale: 60)
        )
    }
}
#endif
