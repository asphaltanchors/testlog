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
    var legacyTestID: String?
    var session: TestSession?
    var product: Product?
    var location: Location?
    var installedDate: Date?
    var testedDate: Date?
    var anchorMaterial: AnchorMaterial?
    var adhesive: Product?
    var holeDiameter: HoleDiameter?
    var cureDays: Int?
    var pavementTemp: Int?
    var brushed: BrushedStatus?
    var testType: TestType?
    var failureMode: FailureMode?
    var mixConsistency: MixConsistency?
    var status: TestStatus
    var notes: String?

    @Relationship(deleteRule: .cascade)
    var measurements: [TestMeasurement] = []

    @Relationship(deleteRule: .cascade)
    var assets: [Asset] = []

    var computedCureDays: Int? {
        guard let installed = installedDate, let tested = testedDate else { return nil }
        return Calendar.current.dateComponents([.day], from: installed, to: tested).day
    }

    init(
        legacyTestID: String? = nil,
        session: TestSession? = nil,
        product: Product? = nil,
        location: Location? = nil,
        installedDate: Date? = nil,
        testedDate: Date? = nil,
        anchorMaterial: AnchorMaterial? = nil,
        adhesive: Product? = nil,
        holeDiameter: HoleDiameter? = nil,
        cureDays: Int? = nil,
        pavementTemp: Int? = nil,
        brushed: BrushedStatus? = nil,
        testType: TestType? = .pull,
        failureMode: FailureMode? = nil,
        mixConsistency: MixConsistency? = nil,
        status: TestStatus = .planned,
        notes: String? = nil
    ) {
        self.legacyTestID = legacyTestID
        self.session = session
        self.product = product
        self.location = location
        self.installedDate = installedDate
        self.testedDate = testedDate
        self.anchorMaterial = anchorMaterial
        self.adhesive = adhesive
        self.holeDiameter = holeDiameter
        self.cureDays = cureDays
        self.pavementTemp = pavementTemp
        self.brushed = brushed
        self.testType = testType
        self.failureMode = failureMode
        self.mixConsistency = mixConsistency
        self.status = status
        self.notes = notes
    }
}
