# Code Review: TestLog

**Date:** 2026-02-20
**Reviewer:** Claude (senior Apple architect perspective)
**Codebase:** ~5,700 lines across 21 Swift files

## Overall Assessment

Well-structured app for its size and velocity. The domain modeling is thoughtful, the SwiftUI patterns are mostly idiomatic, and the protocol-based service layer for video is a good call. The issues below are focused on long-term maintenance — not nitpicks.

---

## What's Working Well

- **Enum-driven sidebar navigation** (`SidebarItem`) — clean, exhaustive switching, easy to extend.
- **Protocol-based video services** — `VideoSyncing`, `VideoExporting`, `AssetStorageManaging` are well-factored contracts. The separation of `VideoServiceContracts.swift` from `DefaultVideoServices.swift` is textbook.
- **Failure hierarchy normalization** in `PullTest` (`normalizeFailureSelections`, `syncFailureFieldsFromModeIfNeeded`) — tricky domain logic handled cleanly with cascading validation.
- **`OptionalEnumPicker`** — nice generic that pays for itself across the whole form.
- **Cascade delete rules** on measurements/assets — correct.
- **Three-column NavigationSplitView** — right pattern for this app's information architecture.

---

## Issues

### P0 — Fix before real data exists

#### ~~P0-1: Add schema versioning~~ Done

**File:** `TestLogApp.swift:28-36`

On schema mismatch, the app deletes the store and starts over. This is fine for development but is a time bomb once real data exists.

**What to do:**
- ~~Add a `VersionedSchema` and `SchemaMigrationPlan`~~
- ~~SwiftData's lightweight migration handles most additions automatically~~
- ~~The nuclear-reset fallback should at minimum back up the old store file before deleting it~~

**Resolution:** Added `SchemaVersioning.swift` with `SchemaV1`, `TestLogMigrationPlan`, and `TestLogContainer`. Store backup before reset. (`df6bad7`)

---

#### ~~P0-2: Store relative paths in Asset.fileURL~~ Done

**File:** `Asset.swift:16`

`var fileURL: URL` stores the full absolute path like `/Users/oren/Library/Application Support/.../Media/T001/{uuid}/video.mov`. If the user migrates to a new machine, restores from backup, or the app container path changes (sandboxed vs non-sandboxed), every stored URL breaks silently.

**What to do:**
- ~~Store a relative path (relative to the media root) instead of the absolute URL~~
- ~~Add a computed property on `Asset` that resolves against `ManagedAssetStorageManager.mediaRootDirectory()` at runtime~~
- ~~Requires a one-time migration of existing data~~

**Resolution:** Renamed `fileURL: URL` to `relativePath: String` with computed `resolvedURL: URL?`. Extracted `MediaPaths` enum for shared media root. Simplified directory structure to `Application Support/Media/` (dropped redundant bundle ID). Updated SchemaV1 stub, protocol contracts, all consumers.

---

### P1 — Important for reliability

#### P1-1: Replace String(describing: persistentModelID) with stable UUID

**Files:** `VideoWorkspaceView.swift:423`, `TestDetailView.swift:578`

```swift
private func assetIdentifier(_ asset: Asset) -> String {
    String(describing: asset.persistentModelID)
}
```

This string is stored in `VideoSyncConfiguration.primaryVideoAssetID` and `equipmentVideoAssetID`. `String(describing:)` on a `PersistentIdentifier` is not guaranteed to be stable across store migrations, re-creation, or CloudKit sync. If SwiftData ever changes the description format, these stored strings become dangling pointers.

**What to do:**
- Give `Asset` an explicit `@Attribute(.unique) var id: UUID` (defaulting to `UUID()` in init)
- Store that UUID (as String or UUID) in `VideoSyncConfiguration.primaryVideoAssetID` / `equipmentVideoAssetID`
- Remove the duplicated `assetIdentifier` helper from both views

---

#### P1-2: Extract VideoWorkspaceCoordinator

**File:** `VideoWorkspaceView.swift` (1043 lines)

This file does four jobs: video preview, timeline editing, sync orchestration, and export orchestration. The view struct owns two `AVPlayer` instances, a time observer token, scrubber state, export state, and sync state.

Any change to the timeline, the export pipeline, or the player lifecycle risks breaking the others. The scrubber-seeking-player-seeking-trimming interaction is already complex enough that `seekPlayersDuringScrub` needs a 40ms throttle.

**What to do:**
- Extract a `VideoWorkspaceCoordinator` (`@Observable` class) that owns:
  - The two `AVPlayer` instances
  - The periodic time observer
  - Playback/seeking/scrubbing state machine
  - Sync and export orchestration methods
- The view becomes a thin shell that reads from the coordinator and forwards user actions
- This also makes the player lifecycle explicit rather than managed via `onAppear`/`onDisappear`/`onChange` chains

---

#### P1-3: Side effect in computed property

**File:** `VideoWorkspaceView.swift:35-43`

```swift
private var syncConfiguration: VideoSyncConfiguration {
    if let existing = test.videoSyncConfiguration {
        return existing
    }
    let config = VideoSyncConfiguration(test: test)
    modelContext.insert(config)
    test.videoSyncConfiguration = config
    return config
}
```

A computed property that inserts into the model context is surprising. SwiftUI can call this getter during any body evaluation.

**What to do:**
- Move this to `onAppear` — ensure the config exists once, then read it normally
- Could also be part of the coordinator extraction (P1-2)

---

### P2 — Code quality and maintainability

#### P2-1: Move grid coordinate logic out of TestDetailView

**File:** `TestDetailView.swift:431-469`

The functions `gridColumnIndex(from:)`, `gridColumnLabel(for:)`, `normalizedGridColumnOrNil(_:)` are pure transformations with no UI dependency. They belong on `Location` or in a small utility.

Right now they're `private` to the view, which means `BulkEditView` or any future grid display can't reuse them.

**What to do:**
- Move to `Location` as static methods, or create a `GridCoordinate` value type
- The coordinate-to-string / string-to-coordinate conversion is a natural pair

---

#### P2-2: Fix BulkEditView failure normalization gap

**File:** `BulkEditView.swift:76-88`

Setting failure family/mechanism/behavior individually doesn't call `normalizeFailureSelections()`. You can set an incompatible family+mechanism combination via bulk edit that `TestDetailView` would prevent.

**What to do:**
- Call `test.normalizeFailureSelections()` after each bulk mutation, same as `TestDetailView` does in its `onChange`

---

#### P2-3: Extract media import pipeline from TestDetailView

**File:** `TestDetailView.swift:611-718`

The entire media import pipeline (file import handling, candidate processing, managed storage copy, tester data parsing) is view-private. If you ever want to import from drag-and-drop, a share extension, or automation, you'd need to extract it.

**What to do:**
- Extract an `AssetImportService` or similar that takes candidates and a test, returns imported assets
- The view calls the service and handles UI feedback

---

#### P2-4: Sidebar badge counting is O(N*M) per render

**File:** `ContentView.swift:104-108`

```swift
ForEach(TestStatus.allCases) { status in
    let count = allTests.filter { $0.status == status }.count
    ...
}
```

Also `siteSidebarRow` at line 212 filters all tests per site. With N tests and M sidebar items, this runs on every render.

**What to do:**
- For sidebar counts, consider separate `@Query` with predicates per status so SwiftData can push filtering to SQLite
- Or compute counts once in a cached dictionary, updated via `onChange(of: allTests.count)`

---

### P3 — Cleanup

#### P3-1: Fix deprecated tracks(withMediaType:) call

**File:** `DefaultVideoServices.swift:205`

```swift
guard let audioTrack = asset.tracks(withMediaType: .audio).first else { return nil }
```

`AVURLAsset.tracks(withMediaType:)` is deprecated since iOS 16 / macOS 13. The rest of the codebase correctly uses `await asset.loadTracks(withMediaType:)`. This one slipped through because it's inside a synchronous static method within `Task.detached`.

**What to do:**
- Make `detectClapPeak` async and use `await asset.loadTracks(withMediaType:)`

---

#### P3-2: Deduplicate clampedNormalized extension

**Files:** `VideoWorkspaceView.swift:857`, `VideoSyncConfiguration.swift:87`

The same `CGRect.clampedNormalized(minSize:)` extension appears in both files as `private`.

**What to do:**
- Make it `internal` in one shared location (e.g., a small `CGRect+Extensions.swift`)

---

#### P3-3: NSView layer timing

**File:** `VideoWorkspaceView.swift:836-838`

```swift
wantsLayer = true
playerLayer.videoGravity = .resizeAspect
layer?.addSublayer(playerLayer)
```

`layer` is optional here. In practice `wantsLayer = true` creates it immediately, but the idiomatic pattern is to override `makeBackingLayer()`.

---

#### P3-4: PullTest.testID has no uniqueness constraint

Users can create two tests with ID "T001". The auto-generation counts existing tests, but if a test is deleted the next one can collide.

**What to do:**
- Add `@Attribute(.unique)` on `testID` with proper error handling on insert
- Or change auto-generation to use a monotonic counter stored separately

---

#### P3-5: Add format documentation to LBYTesterDataParser

**File:** `TesterDataParsing.swift`

The parser has hardcoded magic numbers (byte offsets 256, 608, 800) for a proprietary binary format with no documentation.

**What to do:**
- Add a comment block at the top of the struct describing the binary format layout
- Document the source of the conversion factor (`kN * 1000`, `224.80894387096` lbs/kN)

---

## Things That Are Fine As-Is

- **No unit tests** — the protocol-based services are already shaped for testability when ready.
- **Hardcoded strings** — localization is unnecessary for a small English-only user base.
- **H.264 export** — HEVC would be more efficient but H.264 is more universally compatible.
- **No undo/redo** — SwiftData doesn't make this easy. Acceptable for a small user base.
- **`HoleDiameter` custom Codable** — the backward-compat decoding from decimal strings is load-bearing for SwiftData storage. Keep it.

---

## Quick Reference

| Priority | ID | Issue | Primary File |
|----------|----|-------|-------------|
| ~~P0~~ | ~~P0-1~~ | ~~Add schema versioning~~ Done | `TestLogApp.swift` |
| ~~P0~~ | ~~P0-2~~ | ~~Store relative paths in Asset.fileURL~~ Done | `Asset.swift` |
| P1 | P1-1 | Replace persistentModelID string with stable UUID | `VideoSyncConfiguration.swift`, `Asset.swift` |
| P1 | P1-2 | Extract VideoWorkspaceCoordinator | `VideoWorkspaceView.swift` |
| P1 | P1-3 | Side effect in computed property | `VideoWorkspaceView.swift` |
| P2 | P2-1 | Move grid coordinate logic to model/utility | `TestDetailView.swift` |
| P2 | P2-2 | Fix BulkEditView failure normalization | `BulkEditView.swift` |
| P2 | P2-3 | Extract media import pipeline | `TestDetailView.swift` |
| P2 | P2-4 | Sidebar badge counting performance | `ContentView.swift` |
| P3 | P3-1 | Fix deprecated AVAsset API | `DefaultVideoServices.swift` |
| P3 | P3-2 | Deduplicate clampedNormalized | `VideoWorkspaceView.swift`, `VideoSyncConfiguration.swift` |
| P3 | P3-3 | NSView layer timing | `VideoWorkspaceView.swift` |
| P3 | P3-4 | testID uniqueness constraint | `Test.swift` |
| P3 | P3-5 | Document tester data binary format | `TesterDataParsing.swift` |
