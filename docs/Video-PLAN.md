# Test-Centric Video Analysis Program (Phased, Mac-First)

## Summary
Build video analysis in four phases around the actual operator flow: (1) reliable media attachment + metadata, (2) dedicated video workspace with review/layout/trim controls, (3) timeline alignment (camera sync + tester data alignment), (4) composed export (PiP + metadata + optional force graph).  
Scope is intentionally test-centric (`T###` is the unit), local-first with cloud-ready seams, and no iOS asset UX in this program.

## Current Status (February 21, 2026)
- `Overall`: In active development, major scaffolding complete.
- `Build Health`: macOS and iOS simulator builds passing.
- `Phase 1`: Functionally complete, with remaining UX polish.
- `Phase 2`: Partially complete (dedicated workspace shell implemented with layout toggle, trim, role selection, sync/export actions).
- `Phase 3`: Partially complete (offset model + fallback sync + tester parser + tester max extraction).
- `Phase 4`: Partially complete (export works; needs workflow polish + API modernization + full acceptance pass).

### Implemented So Far
- Asset model expanded for video/tester metadata (`byteSize`, checksum, duration, fps, dimensions, managed-copy flag, role).
- Added `AssetType.testerData` and `VideoRole`.
- Added `VideoSyncConfiguration` model and linked one-to-one with `PullTest`.
- Added typed helpers on `PullTest` for video/tester assets and cardinality validation.
- Added video service contracts and default implementations (storage, validation, metadata probe, sync, export, tester parser).
- Added macOS media workflow in test detail:
  - attach files
  - role assignment review
  - remove assets with safe managed-file cleanup
  - sync controls (primary/equipment selection, auto + manual offsets, trim in/out)
  - composed export with save panel and re-attach as export asset
- Updated duplicate test behavior to avoid copying attachments.
- Updated macOS entitlement to `ENABLE_USER_SELECTED_FILES = readwrite`.
- Tester binary import now extracts and persists a rounded peak force measurement for at-a-glance table visibility.

## Target User Workflow (Updated)
1. User attaches files to a test at any time (single or bulk, all at once or incrementally).
2. User enters a dedicated `Video Workspace` for that test.
3. User reviews the loaded videos in a stable comparison layout (toggle `PiP` / `Side by Side`) and chooses primary/equipment roles if needed.
4. User sets manual trim in/out to isolate the segment of interest.
5. User aligns timeline data:
   - camera-to-camera sync (auto clap + manual offset)
   - tester-data to video timeline (manual offset, with optional future auto hinting)
6. User exports and saves to chosen location; output is attached back as `Export` asset.

### Active Polish / Follow-up
- Import sheet sizing still needs additional visual tightening for sparse content.
- Import progress UX improved (instant button state), but keep validating responsiveness with large/network files.
- Export composition currently uses AVFoundation APIs with deprecation warnings on newest SDK; functional but slated for modernization pass.
- Video workspace is now a separate screen, but playback is not yet time-linked between feeds and tester-data offset controls are not added yet.

## Locked Product Decisions
1. First slice is attachment + metadata only (no sync/composition yet).
2. Assets are copied into managed app storage.
3. Mac-only workflow for this feature program.
4. Architecture stays inside existing app target.
5. Test model remains test-only for now (no `TestSession` modeling in this program).
6. Videos: max 2 per test, any single video is acceptable.
7. Binary: max 1 tester binary per test.
8. Duplicate test does not copy attachments.
9. Removing an asset deletes physical file only if unreferenced.
10. Video import: MOV/MP4/M4V with 1 GB per-file cap.
11. Sync: auto clap detection plus manual fine-tune.
12. Before parser integration: no force graph overlay.
13. Export layout: primary full-frame + gauge PiP.
14. Export audio: primary track only.
15. Export requires manual in/out points.
16. Export save: user-selected location, then attach output as `Export` asset.
17. macOS entitlement should allow user-selected read/write.
18. Stable sample corpus will be provided for validation.
19. Bulk picker + role-assignment UX for attachment.
20. Parser phase will include handoff from your existing Python parser reference.
21. Default export preset: 1080p H.264 30 fps.

## Public API / Interface Changes
1. Update `/Users/oren/src/TestLog/TestLog/Models/Enums.swift`.
2. Extend `AssetType` with a dedicated tester-data case (for explicit binary semantics).
3. Add `VideoRole` enum with values for suggested role assignment (`anchorView`, `equipmentView`, `unassigned`).
4. Update `/Users/oren/src/TestLog/TestLog/Models/Asset.swift` with optional metadata fields: `byteSize`, `contentType`, `checksumSHA256`, `durationSeconds`, `frameRate`, `videoWidth`, `videoHeight`, `isManagedCopy`, `videoRole`.
5. Add typed helpers in `/Users/oren/src/TestLog/TestLog/Models/Test.swift` for `videoAssets`, `testerBinaryAsset`, and validation entrypoints.
6. Add service protocols (new files under `/Users/oren/src/TestLog/TestLog/Services/Video/`): `AssetStorageManaging`, `AssetMetadataProbing`, `AssetValidation`, `VideoSyncing`, `VideoExporting`.
7. Add a sync configuration model (new SwiftData model) for offsets and trims, linked one-to-one to a `PullTest`.
8. Update project setting in `/Users/oren/src/TestLog/TestLog.xcodeproj/project.pbxproj`: `ENABLE_USER_SELECTED_FILES = readwrite` for Debug/Release.

## Implementation Plan

### Phase 1: Attachment Foundation (ship first)
1. Add asset typing/role metadata and optional technical metadata fields.
2. Implement managed-copy storage service under app support path `Media/<testID-or-modelID>/<assetID>/...`.
3. Implement import pipeline: validate type/count/size, copy file, probe metadata via `AVAsset`, compute checksum, persist `Asset`.
4. Add bulk attachment UI to `/Users/oren/src/TestLog/TestLog/Views/TestDetailView.swift` with one flow: select files, assign roles, confirm.
5. Enforce invariants in model/service boundary: max two videos, max one binary.
6. Update duplicate behavior in `/Users/oren/src/TestLog/TestLog/Views/TestTableView.swift` to skip asset duplication.
7. Implement safe cleanup: remove file on asset deletion only when unreferenced.
8. Acceptance for phase: attach/remove/replace flows are stable, metadata visible, and no orphaned behavior regressions.

### Phase 2: Dedicated Video Workspace (UX-first)
1. Add a dedicated `Video Workspace` entry point from test detail (not mixed into the long test form).
2. Build preview area with layout toggle (`PiP` and `Side by Side`) and clear primary/equipment role controls.
3. Add explicit trim controls (in/out sliders + numeric fields) as first-class workflow step before alignment/export.
4. Keep interaction non-blocking and visible (progress indicators, disabled states, no beachball on long operations).
5. Acceptance: user can open workspace and confidently perform review + role selection + trim in one focused screen.

### Phase 3: Timeline Alignment
1. Implement real clap-based camera sync (audio peak matching) with deterministic fallback.
2. Persist camera sync decisions (auto and manual offsets) on `VideoSyncConfiguration`.
3. Add tester-data timeline alignment controls (manual tester-data offset against video timeline).
4. Keep single-video tests cleanly bypassing camera sync while still allowing tester-data alignment.
5. Acceptance: alignment state is persisted and reusable for export without recomputation.

### Phase 4: Export Pipeline and Overlay
1. Keep export pipeline at 1080p H.264 30fps with primary full frame, equipment PiP, and primary audio only.
2. Require trims before export and honor persisted alignment offsets.
3. Include tester force graph overlay when parser data is available and aligned; fallback cleanly if unavailable.
4. Route output through save panel and re-attach as `AssetType.export`.
5. Modernize deprecated AVFoundation composition calls on the latest SDK.
6. Acceptance: reproducible export output for single/dual video tests with aligned tester overlay where available.

## Test Cases and Scenarios
1. Import one valid video under 1 GB and confirm metadata persistence.
2. Import two videos and verify role assignment suggestions and max-two enforcement.
3. Attempt third video import and assert validation error.
4. Import tester binary and verify max-one enforcement.
5. Duplicate test and confirm no assets are copied.
6. Delete asset from one test while referenced elsewhere and confirm file is retained.
7. Delete last reference to asset and confirm physical file cleanup.
8. Workspace opens from test detail and shows all attached media for that test.
9. Layout toggle (`PiP` / `Side by Side`) works and preserves selected primary/equipment assets.
10. Trim controls set and persist valid in/out range; export gate blocks until valid.
11. Auto-sync succeeds on clap-marked pair and manual camera offset persists.
12. Tester data offset persists and is applied in export timeline mapping.
13. Export produces H.264 1080p 30fps with primary audio only.
14. Export file save to user-selected path succeeds with read/write entitlement.
15. Exported file is added back to test as `Export` asset.
16. Parser unavailable path exports without graph.
17. Parser available path exports with graph aligned to timeline.
18. Existing store opens after schema changes with no destructive reset path triggered.

## Assumptions and Defaults
1. User overrides requirements-doc `TestSession` concept for this feature program; work remains strictly per-test.
2. iOS asset UI is out of scope for these phases.
3. Stabilization/tracking (Vision-based gauge stabilization) remains V2 and out of scope now.
4. Binary parser details are deferred until phase 4 handoff from existing Python implementation.
5. Local-first storage is implemented with clean abstraction seams for later cloud migration.
6. Existing non-video/domain gaps (for example status enum breadth and grid-size mismatch) are not expanded in this feature unless they block video workflow correctness.
