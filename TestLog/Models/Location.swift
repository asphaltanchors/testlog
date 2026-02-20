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
    var mode: LocationReferenceMode
    var label: String?
    var gridColumn: String?
    var gridRow: Int?
    var gridSubcell: String?
    var imageX: Double?
    var imageY: Double?
    var notes: String?

    var site: Site?

    @Relationship(inverse: \PullTest.location)
    var test: PullTest?

    var displayLabel: String {
        if let label, !label.isEmpty {
            return label
        }

        switch mode {
        case .gridCell, .imageGridCell:
            var result = "\(gridColumn ?? "?")\(gridRow.map(String.init) ?? "?")"
            if let gridSubcell, !gridSubcell.isEmpty {
                result += "-\(gridSubcell)"
            }
            return result
        case .imagePin:
            return "Pinned Location"
        }
    }

    init(
        mode: LocationReferenceMode = .gridCell,
        label: String? = nil,
        site: Site? = nil,
        gridColumn: String? = nil,
        gridRow: Int? = nil,
        gridSubcell: String? = nil,
        imageX: Double? = nil,
        imageY: Double? = nil,
        notes: String? = nil
    ) {
        self.mode = mode
        self.label = label
        self.site = site
        self.gridColumn = gridColumn
        self.gridRow = gridRow
        self.gridSubcell = gridSubcell
        self.imageX = imageX
        self.imageY = imageY
        self.notes = notes
    }
}
