# Asphalt Anchors Test Management System
## Requirements & Data Model Discovery Document

*Purpose: Input document for a new coding session. Captures domain knowledge, data model, and system requirements.*

---

## 1. Domain Overview

Asphalt Anchors manufactures anchoring products designed to be installed into asphalt surfaces. Testing involves physically installing an anchor and then performing a destructive pull test to measure holding force under various conditions. Because the pull test is destructive, each installation is tested exactly once — installation and test are the same lifecycle event.

The business currently tracks ~122 tests in a flat spreadsheet that has proven inadequate as the variable space grows (products, adhesives, materials, hole sizes, cure times, etc.).

---

## 2. System Components

### 2a. Test Management App (Mac + iOS)
- Mac: Primary data entry, review, analysis, reporting
- iOS: Field data collection during test sessions
- Sync: iCloud (single user, no cloud backend required initially)
- Storage: SwiftData with CloudKit sync option

### 2b. Video Production Tool (Mac)
- Ingests test session data from the Test Management system
- Synchronizes two video files using audio clap detection
- Overlays timestamped test data and force graphs on video
- Exports a composed video artifact (picture-in-picture + data overlay)
- Covered separately; shares the same data store

---

## 3. SwiftData Model

### Entity: Product
Represents an anchor product variant.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| sku | String | e.g. "SP10", "SP12", "SP18", "SP58", "SP88" |
| displayName | String | Human-readable name |
| notes | String? | Optional product notes |

*Products are a lookup/reference table. New products added as they are developed.*

---

### Entity: TestSession
Represents a day or outing in the field where multiple tests are conducted.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| sessionDate | Date | Date of the field session |
| notes | String? | General session notes |
| weatherConditions | String? | Optional ambient conditions |

*Groups related tests. Enables "show me everything from the Sept 12 session" queries.*

---

### Entity: Site
Represents a physical testing area (main pad or ad hoc locations).

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| name | String | Human-readable site name, e.g. "Main Pad" |
| notes | String? | Site notes |
| isPrimaryPad | Bool | Marks the default site for new tests |
| gridColumns | Int? | Optional fixed grid width for structured sites |
| gridRows | Int? | Optional fixed grid height for structured sites |

---

### Entity: Test
The core record. Represents a single anchor installation and its destructive pull test. One installation = one test.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| testID | String? | Primary human-readable test identifier, e.g. "T001" |
| session | TestSession | Parent session (required) |
| product | Product | Which anchor was tested (required) |
| site | Site? | Physical site where the test occurred |
| location | Location? | Physical location reference (optional) |
| installedDate | Date? | When anchor was installed |
| testedDate | Date? | When pull test was performed |
| anchorMaterial | String (enum) | Anchor coating/finish: "Zinc", "Stainless" |
| adhesive | String (enum) | e.g. "ROK700", "Quikrete", "Damtite" |
| holeDiameter | String (enum) | e.g. "7/8\"", "1.125\"", "1.25\"", "1.5\"" |
| cureDays | Int? | Days between installation and test |
| pavementTemp | Int? | Surface temp at test time (°F) |
| brushed | String (enum) | "Y", "N", "Partial" |
| testType | String (enum) | "Pull" (others possible in future) |
| failureMode | String (enum)? | e.g. "Clean Pull", "Snapped Head", "Head Popped Off", "Partial" |
| mixConsistency | String (enum)? | e.g. "Thin", "Standard", "Thick", "Watered Down" |
| notes | String? | Freeform observations |
| videoAssets | [Asset] | Associated video files |

**Computed/derived:**
- `cureDays` can be computed from installedDate → testedDate but worth storing explicitly for cases where one date is missing

**Enums to define explicitly** (will become picker options in UI):
- pavementMaterial
- adhesive
- holeDiameter
- brushed
- testType
- failureMode
- mixConsistency

*Note: These start as string enums for flexibility. If the value space stabilizes, they can become proper lookup tables.*

---

### Entity: Measurement
Represents a single point on the force-displacement curve for a test. Replaces the fixed P1-P5 columns with a flexible child table.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| test | Test | Parent test |
| label | String | e.g. "Slip", "Displacement-Limited", "Allowable Movement", "Diagnostic Peak", "Residual" |
| force | Double? | Force in lbs |
| displacement | Double? | Displacement in inches (often null for current data) |
| timestamp | Date? | For future sensor-captured data |
| isManual | Bool | True = hand-entered, False = captured from instrument |
| sortOrder | Int | Display ordering |

*This model accommodates both the current manual P1-P5 approach and future automated data capture without schema changes. Labels start as freeform strings and can be normalized to a lookup table later.*

---

### Entity: Location
Maps a test to a physical location reference. Supports grid and image-based mapping.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| site | Site? | Site this location belongs to |
| mode | String (enum) | `gridCell`, `imagePin`, `imageGridCell` |
| label | String? | Optional custom label |
| gridColumn | String? | Grid column for grid modes |
| gridRow | Int? | Grid row for grid modes |
| gridSubcell | String? | Optional subcell for offset patterns |
| imageX | Double? | Normalized image X coordinate (0-1) |
| imageY | Double? | Normalized image Y coordinate (0-1) |
| displayLabel | String | Computed summary label |
| test | Test? | The test at this location (one-to-one, permanent) |
| notes | String? | Optional notes about this location |

*For the main pad, grid references remain a shared permanent resource where consumed cells are not reused.*

---

### Entity: Asset
Files associated with a test — videos, photos, documents.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| test | Test | Parent test |
| assetType | String (enum) | "Video", "Photo", "Export", "Document" |
| filename | String | Original filename |
| fileURL | URL | Local or iCloud path |
| createdAt | Date | |
| notes | String? | e.g. "overhead camera", "gauge camera" |

---

## 4. Key Relationships

```
TestSession ──< Test >── Product
                 │
                 ├──< Measurement
                 ├──< Asset
                 ├──── Location
                 └──── Site
```

---

## 5. Discovered Domain Rules

- **Anchor material is always Zinc or Stainless:** This describes the anchor's coating/finish, not the pavement. All testing to date has been on the same asphalt surface at one site.
- **Location grid is permanent:** The 50×15 pad has fixed 1-foot grid positions. Once a cell is used it is permanently consumed. Grid position is recorded to ensure 1-foot separation and prevent interaction between adjacent anchors.
- **Cure time matters:** The gap between installed date and tested date (cure days) is a significant experimental variable.
- **Hole diameter is a controlled variable:** Currently buried in notes, should be a first-class field. Recent tests (T108-T122) are explicitly varying this.
- **Brushed status affects results:** Whether the hole was brushed before adhesive application. Three states: Y, N, Partial.
- **Failure mode is an outcome:** "Snapped head off", "head popped off" etc. indicate anchor failure vs. adhesive failure — scientifically significant distinction.
- **Mix consistency is a variable:** Adhesive mix ratio/consistency affects results. Currently freeform, should be enumerated.
- **Some tests are invalid/ignored:** e.g. T013/T014 (no dates), T015 ("IGNORE"). Need a test status field or soft-delete approach.
- **Test IDs:** Keep sequential IDs (e.g., T001, T122) stable for shorthand communication and traceability.

---

## 6. Test Status / Validity

Tests can be in various states. Recommend a `status` enum on the Test entity:

- `planned` — reserved ID, not yet installed
- `installed` — installed, awaiting test
- `completed` — tested, data recorded
- `invalid` — excluded from analysis (e.g. T015)
- `partial` — tested but data incomplete

---

## 7. iOS Field App Requirements

**Goal:** Capture structured field notes during a test session, synced to Mac via iCloud.

**Workflow:**
1. Create or join a TestSession for the day
2. For each test: fill out a form capturing installation parameters
3. After pull test: enter measurement outcomes (P-values)
4. Add freeform notes
5. Data syncs automatically; Mac app picks it up for analysis and video production

**Form fields (in logical field order):**
- Test ID (auto-assigned sequential format, e.g. `T001`)
- Product (picker)
- Site (picker)
- Location (grid picker, image pin, or image-grid cell)
- Adhesive (picker)
- Hole Diameter (picker)
- Mix Consistency (picker)
- Brushed (picker: Y / N / Partial)
- Pavement Temp (numeric)
- Installed Date/Time (defaults to now)
- Tested Date/Time (defaults to now, can differ from installed)
- Measurements (P1-P5 or flexible entry)
- Failure Mode (picker)
- Notes (freeform text)

**Nice to have:**
- Quick-duplicate last test with edits (common when running a series)
- Clap audio marker (tap button → records timestamp → used for video sync)
- Photo capture attached to test record

---

## 8. Mac App Requirements

**Primary views:**
- Test list with filtering (by product, adhesive, date range, status)
- Test detail / edit form
- Session view (all tests from one day)
- Analysis view (charts: force by variable, comparison across products/adhesives)

**Data operations:**
- CSV import (one-time migration of existing spreadsheet)
- Export to CSV/Excel for sharing
- Filter and export subsets for analysis

**Video integration:**
- Associate video assets with a test or session
- Hand off to Video Production tool with relevant test data

---

## 9. Video Production Tool Requirements

*(Separate tool, shares data store)*

**Inputs:**
- Two video files (e.g. overhead + gauge camera)
- Test session data (timestamped measurements)

**Processing:**
- Clap detection to sync two video timelines
- Manual offset slider for fine-tuning
- Data track aligned to video by absolute timestamp (device clocks accurate to <1 second)

**Output composition:**
- Primary video (full frame)
- Inset video (picture-in-picture, stabilized on gauge region)
- Force graph overlay (time-synced to video)
- Test metadata overlay (product, adhesive, test ID, etc.)

**Stabilization approach:**
- Vision framework object tracking on gauge region
- Apply compensating transforms per frame
- V2 feature — ship without initially

**Export:**
- Single composed video file
- Suitable for customer documentation, instructional content, R&D records

---

## 10. Open Questions / Future Considerations

- **Multiple sites:** All testing to date is at a single site with a 50×15 asphalt pad. If future sites are added, a Site entity would be needed with per-site grids and potentially pavement surface characteristics (age, mix type, etc.). Not modeled now.
- **Pavement surface variation:** Currently no variation — all tests on the same asphalt. If site variation becomes relevant, surface properties would attach to the Site entity.
- **Automated data capture:** Future integration with a digital force gauge. Measurement entity is designed to accommodate this (isManual flag, timestamp field).
- **Experiments:** Tests are often run in groups (e.g. 3 adhesives × 3 reps = 9 tests in one session). Not formally modeled — session grouping and consistent variable values provide sufficient grouping for now. Can add an Experiment entity later if needed.
- **Reporting outputs:** What formats are needed for customers or internal decision-making? Comparison tables, spec sheets, etc. — to be defined.
- **Grid visualization:** A visual 50×15 grid map showing used/available cells would be useful in the Mac app for planning test placement.

---

*Document version: 1.0 — February 2026*
*To be used as context input for implementation coding session.*
