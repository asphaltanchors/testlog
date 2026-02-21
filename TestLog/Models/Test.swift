//
//  Test.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//

import Foundation
import SwiftData

@Model
final class PullTest {
    static let testerMaxMeasurementLabel = "Tester Max"

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

    var computedCureDays: Int? {
        guard let installed = installedDate, let tested = testedDate else { return nil }
        return Calendar.current.dateComponents([.day], from: installed, to: tested).day
    }

    var status: TestStatus {
        computedStatus()
    }

    func computedStatus(referenceDate: Date = .now) -> TestStatus {
        if testedDate != nil {
            return .completed
        }

        guard let installedDate else {
            return .planned
        }

        if installedDate > referenceDate {
            return .planned
        }

        return .installed
    }

    init(
        testID: String? = nil,
        product: Product? = nil,
        site: Site? = nil,
        location: Location? = nil,
        installedDate: Date? = nil,
        testedDate: Date? = nil,
        anchorMaterial: AnchorMaterial? = nil,
        adhesive: Product? = nil,
        holeDiameter: HoleDiameter? = nil,
        cureDays: Int? = nil,
        pavementTemp: Int? = nil,
        brushSize: BrushSize? = .oversized,
        testType: TestType? = .pull,
        failureFamily: FailureFamily? = nil,
        failureMechanism: FailureMechanism? = nil,
        failureBehavior: FailureBehavior? = nil,
        failureMode: FailureMode? = nil,
        notes: String? = nil
    ) {
        self.testID = testID
        self.product = product
        self.site = site
        self.location = location
        self.installedDate = installedDate
        self.testedDate = testedDate
        self.anchorMaterial = anchorMaterial
        self.adhesive = adhesive
        self.holeDiameter = holeDiameter
        self.cureDays = cureDays
        self.pavementTemp = pavementTemp
        self.brushSize = brushSize
        self.testType = testType
        self.failureFamily = failureFamily
        self.failureMechanism = failureMechanism
        self.failureBehavior = failureBehavior
        self.failureMode = failureMode
        self.notes = notes
    }

    func syncFailureFieldsFromModeIfNeeded() {
        guard failureFamily == nil, failureMechanism == nil, failureBehavior == nil, let failureMode else { return }

        switch failureMode {
        case .cleanPull:
            failureFamily = .bondPullout
            failureMechanism = .progressivePullout
            failureBehavior = .progressive
        case .snappedHead:
            failureFamily = .anchorStructural
            failureMechanism = .headWasherInterface
            failureBehavior = .catastrophic
        case .headPoppedOff:
            failureFamily = .anchorStructural
            failureMechanism = .shankMaterialFracture
            failureBehavior = .catastrophic
        case .partial:
            failureFamily = .other
        }
    }

    func normalizeFailureSelections() {
        let families = FailureFamily.options(for: testType)
        if let failureFamily, !families.contains(failureFamily) {
            self.failureFamily = nil
        }

        let mechanisms = FailureMechanism.options(for: testType, family: failureFamily)
        if mechanisms.count == 1 {
            self.failureMechanism = mechanisms.first
        } else if let failureMechanism, !mechanisms.contains(failureMechanism) {
            self.failureMechanism = nil
        }

        let behaviors = FailureBehavior.options(for: failureFamily)
        if behaviors.count == 1 {
            self.failureBehavior = behaviors.first
        } else if let failureBehavior, !behaviors.contains(failureBehavior) {
            self.failureBehavior = nil
        }
    }

    var videoAssets: [Asset] {
        assets.filter { $0.assetType == .video }
    }

    var testerBinaryAsset: Asset? {
        assets.first { $0.assetType == .testerData }
    }

    var hasValidAssetCardinality: Bool {
        videoAssets.count <= 2 && assets.filter { $0.assetType == .testerData }.count <= 1
    }

    var validationIssues: [String] {
        var issues: [String] = []
        if videoAssets.count > 2 {
            issues.append("Only up to 2 video files are allowed per test.")
        }
        if assets.filter({ $0.assetType == .testerData }).count > 1 {
            issues.append("Only 1 tester binary file is allowed per test.")
        }
        return issues
    }

    var peakForceLbs: Double? {
        measurements.compactMap(\.force).max()
    }

    func upsertTesterMaxMeasurement(forceLbs: Double) {
        guard forceLbs.isFinite else { return }
        let roundedForce = forceLbs.rounded()
        if let measurement = testerMaxMeasurement {
            measurement.force = roundedForce
        } else {
            let nextSortOrder = (measurements.map(\.sortOrder).max() ?? -1) + 1
            let measurement = TestMeasurement(
                test: self,
                label: Self.testerMaxMeasurementLabel,
                force: roundedForce,
                displacement: nil,
                timestamp: nil,
                isManual: false,
                sortOrder: nextSortOrder
            )
            measurements.append(measurement)
        }
    }

    func removeTesterMaxMeasurement() {
        if let measurement = testerMaxMeasurement {
            measurements.removeAll { $0.persistentModelID == measurement.persistentModelID }
        }
    }

    private var testerMaxMeasurement: TestMeasurement? {
        measurements.first { $0.label == Self.testerMaxMeasurementLabel && $0.isManual == false }
    }
}
