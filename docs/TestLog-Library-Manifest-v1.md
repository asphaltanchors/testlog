# TestLog.library Manifest Schema v1

## Status
- Draft v1
- Date: February 23, 2026
- Applies to: `TestLog.library/Manifest.json`

## Purpose
`Manifest.json` is the compatibility and integrity anchor for a `TestLog.library` package.

It provides:
1. Format identity (`format`, `manifestVersion`).
2. Package metadata (creation/update, app/build provenance).
3. Relative path contract for database and file roots.
4. Optional integrity metadata for safer backup/transfer validation.

## File Location
- Required path: `TestLog.library/Manifest.json`
- Encoding: UTF-8 JSON

## Top-Level JSON Object (v1)

Required fields:
1. `format` (`string`)
- Must be exactly: `"com.testlog.library"`

2. `manifestVersion` (`integer`)
- Must be exactly: `1`

3. `libraryId` (`string`, UUID format recommended)
- Stable identifier for this library package.
- Must not change after creation.

4. `createdAt` (`string`, ISO-8601 UTC timestamp)
- Initial package creation time.

5. `updatedAt` (`string`, ISO-8601 UTC timestamp)
- Last manifest write/update time.

6. `database` (`object`)
- Required fields:
  - `engine` (`string`): `"swiftdata-sqlite"` for v1
  - `relativePath` (`string`): path to primary store directory/file under package root.
- Example: `"Database/"`

7. `files` (`object`)
- Required fields:
  - `testsRelativePath` (`string`): tester binary root (example: `"Files/tests/"`)
  - `videosRelativePath` (`string`): video root (example: `"Files/videos/"`)

Optional fields:
1. `app` (`object`)
- `bundleIdentifier` (`string`)
- `version` (`string`)
- `build` (`string`)

2. `integrity` (`object`)
- `manifestChecksumSHA256` (`string`) checksum of canonicalized manifest payload (excluding this field if used).
- `databaseSnapshotChecksumSHA256` (`string`) checksum for latest DB snapshot artifact.
- `lastVerifiedAt` (`string`, ISO-8601 UTC timestamp)

3. `migration` (`object`)
- `minimumReadableManifestVersion` (`integer`)
- `minimumReadableAppVersion` (`string`)
- `notes` (`string`)

4. `extensions` (`object`)
- Reserved vendor/app-specific additive metadata.
- Consumers must ignore unknown keys.

## Example `Manifest.json` (v1)
```json
{
  "format": "com.testlog.library",
  "manifestVersion": 1,
  "libraryId": "5D8E5E4C-A3DB-4CA0-9A8B-6A0C0E2E8D8B",
  "createdAt": "2026-02-23T18:40:00Z",
  "updatedAt": "2026-02-23T18:40:00Z",
  "database": {
    "engine": "swiftdata-sqlite",
    "relativePath": "Database/"
  },
  "files": {
    "testsRelativePath": "Files/tests/",
    "videosRelativePath": "Files/videos/"
  },
  "app": {
    "bundleIdentifier": "com.testlog.app",
    "version": "1.0",
    "build": "100"
  }
}
```

## Validation Rules
1. All configured paths must be relative (no absolute paths).
2. Paths must resolve inside the package root (no `..` traversal escapes).
3. `format` and `manifestVersion` must be validated before any DB open attempt.
4. Unknown top-level keys are allowed and ignored unless explicitly required by a future version.
5. Timestamps should be written in UTC with `Z` suffix.

## Versioning and Migration Policy
1. `manifestVersion` increments only for incompatible manifest schema changes.
2. Additive fields in v1 do not require version bump.
3. App must fail safely (read-only or explicit error) for unsupported newer manifest versions.
4. When migrating manifest content, preserve original `libraryId`.
5. Migration actions should be logged in app diagnostics.

## Recovery and Backup Notes
1. Back up/copy the entire `.library` package as one unit.
2. On open, if manifest is missing or invalid, app should not mutate package until user confirms recovery flow.
3. Optional integrity checks should be advisory unless user enables strict mode.

## Interop Notes
1. This manifest does not define cloud sync behavior.
2. Bridge/import-export tooling may use `libraryId` + timestamps for lineage, but must not assume shared live database access.
