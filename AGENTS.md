# AGENTS.md

This file defines how coding agents should work in this repository.

## Source of truth
- Product requirements live in `/Users/oren/src/TestLog/docs/AsphaltAnchors_TestSystem_Requirements.md`.
- If implementation conflicts with that document, follow the document unless the user explicitly overrides it.

## Product context
- App: `TestLog` (SwiftUI + SwiftData), targeting macOS and iOS.
- Domain: destructive pull-testing of asphalt anchors.
- Critical rule: one installation corresponds to one test lifecycle event.

## Core entities
Agents should preserve and evolve these entities:
- `Product`
- `TestSession`
- `PullTest` (domain "Test")
- `TestMeasurement`
- `Location`
- `Asset`

## Domain rules that must be enforced
- `PullTest.session` is required for valid records.
- `PullTest.product` (anchor product) is required for valid records.
- Location grid is permanent and non-reusable per cell once consumed.
- Grid dimensions are fixed at 50 columns (A-AX) x 15 rows.
- `legacyTestID` must remain available for migrated IDs like `T001`.
- Test status must support: `planned`, `installed`, `completed`, `invalid`, `partial`.
- Cure-day logic should prefer computed value from installed->tested dates, with optional manual override.

## Data modeling guidance
- Prefer explicit enums for constrained fields (hole diameter, brushed, test type, failure mode, mix consistency, asset type).
- Keep schema evolution backward-compatible for existing local SwiftData stores when possible.
- Keep relationships explicit and predictable; avoid hidden magic in view logic.
- Validate invariants near the model boundary (creation/update helpers or dedicated validators), not only in UI.

## UI expectations
- iOS supports field capture workflow (session -> test form -> measurements -> notes).
- Mac supports list/detail workflows with filtering and bulk editing.
- Form controls should mirror domain language from requirements.
- Do not remove fields required by the requirements document, even if not yet used in analysis.

## Engineering standards
- Keep code simple, typed, and readable.
- Prefer small focused views/models over large monoliths.
- Add comments only when logic is non-obvious.
- Avoid introducing new dependencies without user approval.

## Validation and review checklist
Before finishing changes, agents should verify:
1. Model compiles with `Product`, `TestSession`, `PullTest`, `TestMeasurement`, `Location`, `Asset`.
2. No required test relationships are accidentally optional in workflows.
3. Location uniqueness/consumption rules are preserved.
4. Test creation still auto-generates legacy-format IDs (`T###`) where expected.
5. Status-based filtering and editing still function.
6. Existing data can still be opened after schema changes (or migration plan is documented).

## Out of scope unless requested
- Building the separate video production app/tool.
- Large analytics/reporting systems beyond what current views support.
- Cloud backend services beyond SwiftData/CloudKit usage.

## When requirements are ambiguous
- State the assumption clearly in PR/task notes.
- Choose the option that preserves data integrity and traceability.
- Ask the user before making irreversible schema or migration decisions.
