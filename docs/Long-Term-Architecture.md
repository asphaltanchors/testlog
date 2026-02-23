# TestLog Long-Term Architecture (2026 Direction)

## Status
- Approved working direction
- Date: February 23, 2026
- Purpose: Define the long-term architecture target and the path to get there.

## North Star
Keep a single repository with two app targets and strict module boundaries:
1. `TestLog macOS` (library-first, file-centric workflows).
2. `TestLog iOS` (cloud-first, field-capture workflows).

Shared logic is packaged as persistence-agnostic Swift packages.  
Storage implementations are platform-specific and not shared.

## Why This Direction
1. Maintains velocity and avoids early multi-repo overhead.
2. Preserves a future path to split repositories if ownership/release needs change.
3. Keeps domain rules consistent while allowing storage models to diverge safely.
4. Matches product reality: macOS and iOS are distinct workflows, not one universal storage model.

## Target Repository Shape
```text
TestLog/
  Apps/
    TestLogMac/
    TestLogiOS/
  Packages/
    TestLogDomain/
    TestLogInterop/
    (optional) TestLogFoundation/
  docs/
```

Notes:
1. Folder names are target-state intent; exact Xcode group layout may vary during transition.
2. Existing project structure can evolve toward this shape incrementally.

## Module Responsibilities
1. `TestLogDomain` (shared)
- Domain DTOs/value types for core concepts.
- Enums and lifecycle semantics (including `PullTest.status`: `planned`, `installed`, `completed`).
- Validation/invariants and business rules (including cure-day behavior expectations).
- No SwiftUI, no SwiftData, no CloudKit dependencies.

2. `TestLogInterop` (shared)
- `TestLog.library` manifest models and validation contract.
- Import/export payload schemas and versioning.
- Mapping helpers between app-specific persistence models and shared transfer/domain shapes.

3. `TestLogFoundation` (optional shared)
- Small utilities (ID/date helpers, parsing helpers) that are pure Swift and broadly reused.

4. `TestLogMac` app target (platform-specific)
- `.library` package lifecycle and storage adapters.
- Video/test binary file management.
- macOS-focused list/detail and media workflows.

5. `TestLogiOS` app target (platform-specific)
- Cloud-backed data adapters.
- iOS field capture UX.
- No default syncing of video/test binaries.

## Explicit Non-Goals
1. Do not share persistence model classes directly between macOS and iOS.
2. Do not couple iOS cloud implementation to macOS `.library` implementation.
3. Do not add automatic bidirectional sync between macOS library and iOS cloud in v1.

## Data and Storage Boundary (Authoritative)
1. macOS canonical storage: `TestLog.library` package (DB + files).
2. iOS canonical storage: cloud structured data.
3. Media/test binaries: local to macOS library by default; out of default cross-device sync scope.

Related specs:
1. `docs/Storage-Boundary-Spec.md`
2. `docs/TestLog-Library-Manifest-v1.md`

## Engineering Guardrails
1. Preserve core domain entities: `Product`, `PullTest`, `TestMeasurement`, `Site`, `Location`, `Asset`, `VideoSyncConfiguration`.
2. Preserve lifecycle and cure-day behaviors unless intentionally revised.
3. Keep schema evolution backward-compatible where possible or document migrations.
4. Validate invariants at model/service boundaries, not only in UI.
5. Keep package APIs small and explicit to reduce cross-target coupling.

## Testing Strategy for This Architecture
1. Package-level unit tests in shared modules (`Domain`, `Interop`).
2. Contract tests for manifest/import-export version compatibility.
3. Target-specific integration tests for storage adapters:
- macOS `.library` open/create/migrate/read/write flows.
- iOS cloud CRUD and offline/retry behavior.

## Phased Migration Plan
1. Phase A: Boundary hardening (now)
- Keep current repo, add docs/specs, lock storage boundary decisions.
- Identify code that is currently shared only by convenience.

2. Phase B: Extract shared pure logic
- Move enums/rules/validators/DTOs into `TestLogDomain`.
- Move manifest and transfer contracts into `TestLogInterop`.
- Add mapping layers from app models to shared types.

3. Phase C: Isolate platform persistence
- macOS: complete `.library` storage path and file-store adapters.
- iOS: cloud adapter path and app flow alignment.
- Remove accidental cross-imports.

4. Phase D: Contract-first interoperability
- Add explicit import/export flows using shared interop schema.
- Add version compatibility tests and migration checks.

5. Phase E: Re-evaluate repository split (only if needed)
- Trigger only if team/release/compliance constraints justify it.
- If triggered, move shared packages to a dedicated core repo and consume via package dependency.

## Criteria to Consider a Future Repo Split
1. Distinct teams with independent release trains.
2. CI/build scale pain in a single repo.
3. Access-control or compliance requirements needing separation.

If these are not present, keep monorepo.

## Decision Record
As of February 23, 2026:
1. Preferred long-term architecture is one repo, two platform targets, shared pure Swift packages, separate persistence layers.
2. This decision optimizes long-term maintainability while preserving execution speed now.
