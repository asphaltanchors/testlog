# TestLog

Internal SwiftUI + SwiftData app for tracking asphalt anchor pull tests.

This repo is optimized for day-to-day internal use, not for external onboarding. The notes below are mostly to help friends (or future me) review the code and give feedback quickly.

## What this app does

- Tracks the lifecycle of an anchor pull test (`planned -> installed -> completed`).
- Stores anchor/test metadata, measurements, notes, and linked assets.
- Supports site/location tracking plus product and adhesive catalogs.
- Includes early video/tester-data workflow plumbing for per-test media sync/export.

## Stack

- SwiftUI app (`macOS` + `iOS` target structure in one codebase)
- SwiftData local persistence
- No backend service required for core local workflows

## Project structure

Top-level:

- `TestLog/` main app source
- `TestLog.xcodeproj/` Xcode project
- `docs/` project notes and plans
- `samples/` example/reference files used during development

Inside `TestLog/`:

- `TestLog/TestLogApp.swift`
  - App entrypoint
  - Builds SwiftData `Schema` and `ModelContainer`
- `TestLog/ContentView.swift`
  - Main navigation shell (sidebar/split view)
  - Routes between tests, products, and sites
- `TestLog/Models/`
  - Core domain + persistence models
  - Main entities currently in schema:
    - `PullTest`
    - `Product`
    - `TestMeasurement`
    - `Site`
    - `Location`
    - `Asset`
    - `VideoSyncConfiguration`
  - Constrained value types in `Enums.swift` (test type, failure fields, hole diameter, asset type, etc.)
- `TestLog/Views/`
  - UI screens for list/detail, bulk edit, tables, products, sites, and video workspace
  - Key files include:
    - `TestTableView.swift` / `TestListView.swift`
    - `TestDetailView.swift`
    - `ProductListView.swift` / `ProductTableView.swift`
    - `SiteViews.swift`
    - `BulkEditView.swift`
    - `VideoWorkspaceView.swift`
- `TestLog/Services/Video/`
  - Video/tester-data specific services and contracts
  - Parsing + workflow helpers for media sync pipeline

## Data flow at a glance

1. User creates or edits a `PullTest` from list/table/detail flows.
2. Related records (`TestMeasurement`, `Asset`, `Location`) are attached to that test.
3. Status is derived from installed/tested dates (`planned`, `installed`, `completed`).
4. Optional video sync config and assets support export workflows.

## Notes for reviewers

- Start with:
  - `TestLog/ContentView.swift` for app navigation and feature entry points
  - `TestLog/Models/Test.swift` for core test domain behavior
  - `TestLog/Views/TestDetailView.swift` for the main form/edit workflow
- `docs/Video-PLAN.md` captures the current video workflow direction and assumptions.
- If you review data modeling, check relationship optionality and delete rules first (most behavior hangs off those choices).

## Running locally (minimal)

1. Open `TestLog.xcodeproj` in Xcode.
2. Build/run the `TestLog` target on macOS or iOS simulator.

That is intentionally it for now.
