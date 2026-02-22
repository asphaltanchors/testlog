//
//  SchemaVersioning.swift
//  TestLog
//
//  Created by Claude on 2/20/26.
//

import Foundation
import SwiftData

// MARK: - Schema V1

/// Frozen snapshot of the schema as of initial release.
/// Each versioned schema must be a self-contained description — these stubs
/// duplicate stored properties and relationships only (no computed props or methods).
/// The enum types (ProductCategory, AnchorMaterial, etc.) are Codable value types
/// defined in Enums.swift and shared across all schema versions.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Product.self,
            PullTest.self,
            TestMeasurement.self,
            Site.self,
            Location.self,
            Asset.self,
            VideoSyncConfiguration.self,
        ]
    }

    @Model
    final class Product {
        var name: String
        var category: ProductCategory
        var notes: String?
        var isActive: Bool
        var retiredOn: Date?
        var retirementNote: String?

        @Relationship(inverse: \PullTest.product)
        var tests: [PullTest] = []

        @Relationship(inverse: \PullTest.adhesive)
        var adhesiveTests: [PullTest] = []

        init(
            name: String,
            category: ProductCategory = .anchor,
            notes: String? = nil,
            isActive: Bool = true,
            retiredOn: Date? = nil,
            retirementNote: String? = nil
        ) {
            self.name = name
            self.category = category
            self.notes = notes
            self.isActive = isActive
            self.retiredOn = retiredOn
            self.retirementNote = retirementNote
        }
    }

    @Model
    final class PullTest {
        var testID: String?
        var product: Product?
        var site: Site?
        var location: Location?
        var installedDate: Date?
        var testedDate: Date?
        var anchorMaterial: AnchorMaterial?
        var adhesive: Product?
        var holeDiameter: HoleDiameter?
        var cureDays: Int?
        var pavementTemp: Int?
        var brushSize: BrushSize?
        var testType: TestType?
        var failureFamily: FailureFamily?
        var failureMechanism: FailureMechanism?
        var failureBehavior: FailureBehavior?
        var failureMode: FailureMode?
        var notes: String?

        @Relationship(deleteRule: .cascade)
        var measurements: [TestMeasurement] = []

        @Relationship(deleteRule: .cascade)
        var assets: [Asset] = []

        @Relationship(deleteRule: .cascade)
        var videoSyncConfiguration: VideoSyncConfiguration?

        init() {}
    }

    @Model
    final class TestMeasurement {
        var test: PullTest?
        var label: String
        var force: Double?
        var displacement: Double?
        var timestamp: Date?
        var isManual: Bool
        var sortOrder: Int

        init(
            label: String = "",
            force: Double? = nil,
            displacement: Double? = nil,
            timestamp: Date? = nil,
            isManual: Bool = true,
            sortOrder: Int = 0
        ) {
            self.label = label
            self.force = force
            self.displacement = displacement
            self.timestamp = timestamp
            self.isManual = isManual
            self.sortOrder = sortOrder
        }
    }

    @Model
    final class Site {
        @Attribute(.unique) var name: String
        var notes: String?
        var isPrimaryPad: Bool
        var gridColumns: Int?
        var gridRows: Int?

        init(
            name: String = "",
            notes: String? = nil,
            isPrimaryPad: Bool = false,
            gridColumns: Int? = nil,
            gridRows: Int? = nil
        ) {
            self.name = name
            self.notes = notes
            self.isPrimaryPad = isPrimaryPad
            self.gridColumns = gridColumns
            self.gridRows = gridRows
        }
    }

    @Model
    final class Location {
        var label: String?
        var gridColumn: String?
        var gridRow: Int?
        var notes: String?
        var site: Site?

        @Relationship(inverse: \PullTest.location)
        var test: PullTest?

        init(
            label: String? = nil,
            gridColumn: String? = nil,
            gridRow: Int? = nil,
            notes: String? = nil
        ) {
            self.label = label
            self.gridColumn = gridColumn
            self.gridRow = gridRow
            self.notes = notes
        }
    }

    @Model
    final class Asset {
        var test: PullTest?
        var assetType: AssetType
        var filename: String
        var relativePath: String
        var createdAt: Date
        var notes: String?
        var byteSize: Int64?
        var contentType: String?
        var checksumSHA256: String?
        var durationSeconds: Double?
        var frameRate: Double?
        var videoWidth: Int?
        var videoHeight: Int?
        var isManagedCopy: Bool
        var videoRole: VideoRole?

        init(
            assetType: AssetType = .photo,
            filename: String = "",
            relativePath: String = "",
            createdAt: Date = Date(),
            isManagedCopy: Bool = false
        ) {
            self.assetType = assetType
            self.filename = filename
            self.relativePath = relativePath
            self.createdAt = createdAt
            self.isManagedCopy = isManagedCopy
        }
    }

    @Model
    final class VideoSyncConfiguration {
        @Relationship(inverse: \PullTest.videoSyncConfiguration)
        var test: PullTest?
        var primaryVideoAssetID: String?
        var equipmentVideoAssetID: String?
        var autoOffsetSeconds: Double?
        var manualOffsetSeconds: Double
        var trimInSeconds: Double?
        var trimOutSeconds: Double?
        var lastSyncedAt: Date?
        var equipmentRotationQuarterTurns: Int
        var equipmentCropX: Double
        var equipmentCropY: Double
        var equipmentCropWidth: Double
        var equipmentCropHeight: Double

        init(
            manualOffsetSeconds: Double = 0,
            equipmentRotationQuarterTurns: Int = 0,
            equipmentCropX: Double = 0,
            equipmentCropY: Double = 0,
            equipmentCropWidth: Double = 1,
            equipmentCropHeight: Double = 1
        ) {
            self.manualOffsetSeconds = manualOffsetSeconds
            self.equipmentRotationQuarterTurns = equipmentRotationQuarterTurns
            self.equipmentCropX = equipmentCropX
            self.equipmentCropY = equipmentCropY
            self.equipmentCropWidth = equipmentCropWidth
            self.equipmentCropHeight = equipmentCropHeight
        }
    }
}

// MARK: - Schema V2
// Adds Product.defaultHoleDiameter and Product.ratedStrengthLbs (both optional → lightweight).
// All model stubs must be self-contained within the enum so relationship key paths
// resolve against the correct version's types.

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Product.self,
            PullTest.self,
            TestMeasurement.self,
            Site.self,
            Location.self,
            Asset.self,
            VideoSyncConfiguration.self,
        ]
    }

    @Model
    final class Product {
        var name: String
        var category: ProductCategory
        var notes: String?
        var isActive: Bool
        var retiredOn: Date?
        var retirementNote: String?
        var defaultHoleDiameter: HoleDiameter?
        var ratedStrengthLbs: Int?

        @Relationship(inverse: \PullTest.product)
        var tests: [PullTest] = []

        @Relationship(inverse: \PullTest.adhesive)
        var adhesiveTests: [PullTest] = []

        init() { name = ""; category = .anchor; isActive = true }
    }

    @Model
    final class PullTest {
        var testID: String?
        var product: Product?
        var site: Site?
        var location: Location?
        var installedDate: Date?
        var testedDate: Date?
        var anchorMaterial: AnchorMaterial?
        var adhesive: Product?
        var holeDiameter: HoleDiameter?
        var cureDays: Int?
        var pavementTemp: Int?
        var brushSize: BrushSize?
        var testType: TestType?
        var failureFamily: FailureFamily?
        var failureMechanism: FailureMechanism?
        var failureBehavior: FailureBehavior?
        var failureMode: FailureMode?
        var notes: String?

        @Relationship(deleteRule: .cascade)
        var measurements: [TestMeasurement] = []

        @Relationship(deleteRule: .cascade)
        var assets: [Asset] = []

        @Relationship(deleteRule: .cascade)
        var videoSyncConfiguration: VideoSyncConfiguration?

        init() {}
    }

    @Model
    final class TestMeasurement {
        var test: PullTest?
        var label: String
        var force: Double?
        var displacement: Double?
        var timestamp: Date?
        var isManual: Bool
        var sortOrder: Int

        init() { label = ""; isManual = true; sortOrder = 0 }
    }

    @Model
    final class Site {
        @Attribute(.unique) var name: String
        var notes: String?
        var isPrimaryPad: Bool
        var gridColumns: Int?
        var gridRows: Int?

        init() { name = ""; isPrimaryPad = false }
    }

    @Model
    final class Location {
        var label: String?
        var gridColumn: String?
        var gridRow: Int?
        var notes: String?
        var site: Site?

        @Relationship(inverse: \PullTest.location)
        var test: PullTest?

        init() {}
    }

    @Model
    final class Asset {
        var test: PullTest?
        var assetType: AssetType
        var filename: String
        var relativePath: String
        var createdAt: Date
        var notes: String?
        var byteSize: Int64?
        var contentType: String?
        var checksumSHA256: String?
        var durationSeconds: Double?
        var frameRate: Double?
        var videoWidth: Int?
        var videoHeight: Int?
        var isManagedCopy: Bool
        var videoRole: VideoRole?

        init() { assetType = .photo; filename = ""; relativePath = ""; createdAt = Date(); isManagedCopy = false }
    }

    @Model
    final class VideoSyncConfiguration {
        @Relationship(inverse: \PullTest.videoSyncConfiguration)
        var test: PullTest?
        var primaryVideoAssetID: String?
        var equipmentVideoAssetID: String?
        var autoOffsetSeconds: Double?
        var manualOffsetSeconds: Double
        var trimInSeconds: Double?
        var trimOutSeconds: Double?
        var lastSyncedAt: Date?
        var equipmentRotationQuarterTurns: Int
        var equipmentCropX: Double
        var equipmentCropY: Double
        var equipmentCropWidth: Double
        var equipmentCropHeight: Double

        init() {
            manualOffsetSeconds = 0
            equipmentRotationQuarterTurns = 0
            equipmentCropX = 0; equipmentCropY = 0
            equipmentCropWidth = 1; equipmentCropHeight = 1
        }
    }
}

// MARK: - Schema V3
// Adds PullTest.isValid (Bool, defaults to true → lightweight).

enum SchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Product.self,
            PullTest.self,
            TestMeasurement.self,
            Site.self,
            Location.self,
            Asset.self,
            VideoSyncConfiguration.self,
        ]
    }

    @Model
    final class Product {
        var name: String
        var category: ProductCategory
        var notes: String?
        var isActive: Bool
        var retiredOn: Date?
        var retirementNote: String?
        var defaultHoleDiameter: HoleDiameter?
        var ratedStrengthLbs: Int?

        @Relationship(inverse: \PullTest.product)
        var tests: [PullTest] = []

        @Relationship(inverse: \PullTest.adhesive)
        var adhesiveTests: [PullTest] = []

        init() { name = ""; category = .anchor; isActive = true }
    }

    @Model
    final class PullTest {
        var testID: String?
        var product: Product?
        var site: Site?
        var location: Location?
        var installedDate: Date?
        var testedDate: Date?
        var anchorMaterial: AnchorMaterial?
        var adhesive: Product?
        var holeDiameter: HoleDiameter?
        var cureDays: Int?
        var pavementTemp: Int?
        var brushSize: BrushSize?
        var testType: TestType?
        var failureFamily: FailureFamily?
        var failureMechanism: FailureMechanism?
        var failureBehavior: FailureBehavior?
        var failureMode: FailureMode?
        var notes: String?
        var isValid: Bool

        @Relationship(deleteRule: .cascade)
        var measurements: [TestMeasurement] = []

        @Relationship(deleteRule: .cascade)
        var assets: [Asset] = []

        @Relationship(deleteRule: .cascade)
        var videoSyncConfiguration: VideoSyncConfiguration?

        init() { isValid = true }
    }

    @Model
    final class TestMeasurement {
        var test: PullTest?
        var label: String
        var force: Double?
        var displacement: Double?
        var timestamp: Date?
        var isManual: Bool
        var sortOrder: Int

        init() { label = ""; isManual = true; sortOrder = 0 }
    }

    @Model
    final class Site {
        @Attribute(.unique) var name: String
        var notes: String?
        var isPrimaryPad: Bool
        var gridColumns: Int?
        var gridRows: Int?

        init() { name = ""; isPrimaryPad = false }
    }

    @Model
    final class Location {
        var label: String?
        var gridColumn: String?
        var gridRow: Int?
        var notes: String?
        var site: Site?

        @Relationship(inverse: \PullTest.location)
        var test: PullTest?

        init() {}
    }

    @Model
    final class Asset {
        var test: PullTest?
        var assetType: AssetType
        var filename: String
        var relativePath: String
        var createdAt: Date
        var notes: String?
        var byteSize: Int64?
        var contentType: String?
        var checksumSHA256: String?
        var durationSeconds: Double?
        var frameRate: Double?
        var videoWidth: Int?
        var videoHeight: Int?
        var isManagedCopy: Bool
        var videoRole: VideoRole?

        init() { assetType = .photo; filename = ""; relativePath = ""; createdAt = Date(); isManagedCopy = false }
    }

    @Model
    final class VideoSyncConfiguration {
        @Relationship(inverse: \PullTest.videoSyncConfiguration)
        var test: PullTest?
        var primaryVideoAssetID: String?
        var equipmentVideoAssetID: String?
        var autoOffsetSeconds: Double?
        var manualOffsetSeconds: Double
        var trimInSeconds: Double?
        var trimOutSeconds: Double?
        var lastSyncedAt: Date?
        var equipmentRotationQuarterTurns: Int
        var equipmentCropX: Double
        var equipmentCropY: Double
        var equipmentCropWidth: Double
        var equipmentCropHeight: Double

        init() {
            manualOffsetSeconds = 0
            equipmentRotationQuarterTurns = 0
            equipmentCropX = 0; equipmentCropY = 0
            equipmentCropWidth = 1; equipmentCropHeight = 1
        }
    }
}

// MARK: - Migration Plan

enum TestLogMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
        ]
    }
}

// MARK: - Container Factory

enum TestLogContainer {
    /// The live model types used at runtime for queries and persistence.
    private static let liveModelTypes: [any PersistentModel.Type] = [
        Product.self,
        PullTest.self,
        TestMeasurement.self,
        Site.self,
        Location.self,
        Asset.self,
        VideoSyncConfiguration.self,
    ]

    /// Creates a `ModelContainer` configured with the migration plan.
    /// The schema uses the live model types (for runtime queries) while the
    /// migration plan references the versioned schema stubs (for evolution).
    static func create() -> ModelContainer {
        let schema = Schema(liveModelTypes)
        let configuration = ModelConfiguration(
            "TestLog",
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: TestLogMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            print("ModelContainer creation failed: \(error)")
            print("Backing up store before reset...")
            backupStoreArtifacts()

            do {
                try deleteStoreArtifacts(configurationName: "TestLog")
                return try ModelContainer(
                    for: schema,
                    migrationPlan: TestLogMigrationPlan.self,
                    configurations: [configuration]
                )
            } catch {
                fatalError("Could not create ModelContainer after reset: \(error)")
            }
        }
    }

    /// Deletes store artifacts matching the given configuration name.
    private static func deleteStoreArtifacts(configurationName: String) throws {
        let fileManager = FileManager.default
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        guard fileManager.fileExists(atPath: applicationSupportURL.path) else { return }
        let directoryContents = try fileManager.contentsOfDirectory(
            at: applicationSupportURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for url in directoryContents {
            let fileName = url.lastPathComponent
            if fileName.contains(configurationName) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    /// Copies store files to a timestamped backup directory before the nuclear reset.
    private static func backupStoreArtifacts() {
        let fileManager = FileManager.default
        guard let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: Date())

        let backupDir = appSupport
            .appendingPathComponent("TestLog-Backups", isDirectory: true)
            .appendingPathComponent(timestamp, isDirectory: true)

        do {
            try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
        } catch {
            print("Failed to create backup directory: \(error)")
            return
        }

        guard fileManager.fileExists(atPath: appSupport.path) else { return }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: appSupport,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents where url.lastPathComponent.contains("TestLog") {
            let destination = backupDir.appendingPathComponent(url.lastPathComponent)
            do {
                try fileManager.copyItem(at: url, to: destination)
                print("Backed up: \(url.lastPathComponent)")
            } catch {
                print("Failed to back up \(url.lastPathComponent): \(error)")
            }
        }

        print("Store backup saved to: \(backupDir.path)")
    }
}
