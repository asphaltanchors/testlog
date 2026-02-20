//
//  Location.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//

import Foundation
import SwiftData

@Model
final class Location {
    var gridColumn: String
    var gridRow: Int
    var notes: String?

    @Relationship(inverse: \PullTest.location)
    var test: PullTest?

    var displayLabel: String {
        "\(gridColumn)\(gridRow)"
    }

    init(gridColumn: String, gridRow: Int, notes: String? = nil) {
        self.gridColumn = gridColumn
        self.gridRow = gridRow
        self.notes = notes
    }
}
