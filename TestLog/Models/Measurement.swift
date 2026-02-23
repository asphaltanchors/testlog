//
//  Measurement.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//

import Foundation
import SwiftData

@Model
final class TestMeasurement {
    var test: PullTest?
    var label: String
    var measurementType: MeasurementType?
    var force: Double?
    var displacement: Double?
    var timestamp: Date?
    var isManual: Bool
    var sortOrder: Int

    init(
        test: PullTest? = nil,
        label: String,
        measurementType: MeasurementType? = nil,
        force: Double? = nil,
        displacement: Double? = nil,
        timestamp: Date? = nil,
        isManual: Bool = true,
        sortOrder: Int = 0
    ) {
        self.test = test
        self.label = label
        self.measurementType = measurementType
        self.force = force
        self.displacement = displacement
        self.timestamp = timestamp
        self.isManual = isManual
        self.sortOrder = sortOrder
    }
}
