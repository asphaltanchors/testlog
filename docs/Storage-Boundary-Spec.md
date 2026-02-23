# TestLog Storage Boundary Spec (Mac Library + iOS Cloud)

## Status
- Draft v1
- Date: February 23, 2026
- Scope: Define storage and ownership boundaries between the macOS and iOS apps.

## Goal
Establish a clear split:
- macOS app is file-library centric (`.library` package, user-controlled location).
- iOS app is cloud-data centric (structured records, field capture workflow).

This intentionally replaces a single universal-storage model.

## Non-Goals
- No requirement for direct live sync between `.library` files and iOS cloud in v1.
- No automatic sync of videos or tester binaries between devices.
- No shared-write access to the same SQLite store across devices in v1.

## Product Boundary
1. `TestLog for macOS` (Library Edition)
- Canonical persistence is a user-selected `TestLog.library` package.
- Package contains core database plus all local files (tester binaries and videos).
- App supports backup, copy, and restore by operating on the package.

2. `TestLog for iOS` (Cloud Capture Edition)
- Canonical persistence is cloud-backed structured data.
- Optimized for in-field entry and lightweight updates.
- Heavy media is out of scope for default cross-device sync behavior.

## Library Package Contract (macOS)
Package extension: `.library` (directory bundle).

Expected top-level layout:
- `Database/` (SwiftData/SQLite store files)
- `Files/tests/` (tester binary files)
- `Files/videos/` (video files)
- `Manifest.json` (schema version, app version, metadata)

Notes:
- Internal filenames may evolve, but these top-level folders remain stable.
- `Manifest.json` is the migration/version anchor.

## Data Ownership Matrix
1. Core domain records (`Product`, `PullTest`, `TestMeasurement`, `Site`, `Location`, `Asset`, `VideoSyncConfiguration`)
- macOS: stored in library database.
- iOS: stored in cloud database.
- Cross-platform relation: shared logical schema and identifier format where feasible.

2. Tester binary files
- macOS: stored in `Files/tests/` inside `.library`.
- iOS: not synced by default.

3. Video files
- macOS: stored in `Files/videos/` inside `.library`.
- iOS: not synced by default.

## Cross-App Interop Contract (v1)
Interop is file/API bridge based, not shared live storage.

Bridge requirements:
1. Stable entity IDs for records that may move between apps.
2. Explicit import/export mapping for lifecycle state (`planned`, `installed`, `completed`).
3. Preserve cure-day semantics (`computedCureDays`, optional override) during transfer.
4. Assets transfer as metadata references unless explicitly exported with files.

## Sync and Backup Strategy
1. Backup
- Primary backup unit for macOS is the entire `.library` package.
- Users can back up with any file-level tool (for example Time Machine or external sync folders).

2. Sync
- v1: no automatic bidirectional sync between macOS library and iOS cloud.
- Future: optional bridge/sync process may be added, but must keep media excluded by default.

3. Conflict posture
- v1 assumes single-writer access per library package.
- If future folder-sync is used, app should prefer lock/read-only safeguards over silent merge.

## Guardrails and Invariants
1. One installation corresponds to one test lifecycle event.
2. `PullTest.status` remains aligned to `planned`, `installed`, `completed` unless intentionally expanded.
3. Schema changes must remain backward-compatible where practical, or include migration notes.
4. Relationship/delete behavior must be explicit and documented.

## Open Decisions (Not Blocking v1 Spec)
1. Canonical format/versioning details for `Manifest.json`.
2. Whether iOS supports media capture that remains cloud-external but locally attached.
3. Whether future bridge is manual export/import only or includes scheduled sync jobs.

## Assumptions Recorded
1. macOS and iOS are treated as distinct product surfaces with different storage models.
2. Tiny structured data may sync in the future, but media and tester binaries should not sync by default.
3. Data integrity and traceability are prioritized over seamless live multi-device editing in v1.
