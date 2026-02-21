# AGENTS.md

This file defines how coding agents should work in this repository.

## Source of truth
- The prior requirements document was intentionally removed due to drift.
- Source of truth is now:
  1. Current code in `TestLog/`
  2. Explicit user instructions in the active task
  3. Supporting notes in `docs/` (for example `docs/Video-PLAN.md`)
- If these conflict, follow direct user instructions.

## Product context
- App: `TestLog` (SwiftUI + SwiftData), targeting macOS and iOS.
- Domain: destructive pull-testing of asphalt anchors.
- Critical rule: one installation corresponds to one test lifecycle event.

## Core entities
Agents should preserve and evolve these entities:
- `Product`
- `PullTest` (domain "Test")
- `TestMeasurement`
- `Site`
- `Location`
- `Asset`
- `VideoSyncConfiguration`

## Domain rules that must be enforced
- Preserve behaviors currently implemented in models unless the user requests a change.
- Keep `PullTest.status` aligned with implemented lifecycle states (`planned`, `installed`, `completed`) unless expanded intentionally.
- Keep cure-day behavior consistent with current implementation (`computedCureDays` from installed -> tested dates, with optional stored override field).
- Do not introduce breaking relationship changes without a migration plan.
- If re-introducing older/higher-fidelity domain constraints (session requirements, rigid grid policies, legacy ID semantics), confirm with the user first.

## Data modeling guidance
- Prefer explicit enums for constrained fields (hole diameter, brush size, test type, failure classifications, asset/video types).
- Keep schema evolution backward-compatible for existing local SwiftData stores when possible.
- Keep relationships explicit and predictable; avoid hidden magic in view logic.
- Validate invariants near the model boundary (creation/update helpers or dedicated validators), not only in UI.

## UI expectations
- iOS supports field capture workflow (test form -> measurements -> notes).
- Mac supports list/detail workflows with filtering and bulk editing.
- Form controls should mirror current domain language in models and views.
- Do not remove existing persisted fields lightly; prefer additive changes.

## Engineering standards
- Keep code simple, typed, and readable.
- Prefer small focused views/models over large monoliths.
- Add comments only when logic is non-obvious.
- Avoid introducing new dependencies without user approval.

## Validation and review checklist
Before finishing changes, agents should verify:
1. Model compiles with `Product`, `PullTest`, `TestMeasurement`, `Site`, `Location`, `Asset`, and `VideoSyncConfiguration`.
2. Status-based filtering and editing still function.
3. Existing data can still be opened after schema changes (or migration plan is documented).
4. Relationship and delete-rule behavior is still intentional and documented in code.
5. Any assumptions made due to missing historical requirements are stated in task notes.

## Out of scope unless requested
- Building the separate video production app/tool.
- Large analytics/reporting systems beyond what current views support.
- Cloud backend services beyond SwiftData/CloudKit usage.

## When requirements are ambiguous
- State the assumption clearly in PR/task notes.
- Choose the option that preserves data integrity and traceability.
- Ask the user before making irreversible schema or migration decisions.
