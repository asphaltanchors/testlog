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
    var label: String?
    var gridColumn: Int?
    var gridRow: Int?
    var notes: String?

    var site: Site?

    @Relationship(inverse: \PullTest.location)
    var test: PullTest?

    var displayLabel: String {
        if let label, !label.isEmpty {
            return label
        }

        if let gridCoordinateLabel {
            return gridCoordinateLabel
        }

        return "Unmapped"
    }

    private var gridCoordinateLabel: String? {
        guard let row = gridRow, row > 0 else { return nil }
        guard let column = gridColumn, column > 0 else { return nil }
        return "\(GridCoordinateCodec.gridColumnLabel(for: column))\(row)"
    }

    init(
        label: String? = nil,
        site: Site? = nil,
        gridColumn: Int? = nil,
        gridRow: Int? = nil,
        notes: String? = nil
    ) {
        self.label = label
        self.site = site
        self.gridColumn = gridColumn
        self.gridRow = gridRow
        self.notes = notes
    }
}
