//
//  Site.swift
//  TestLog
//
//  Created by Oren Teich on 2/20/26.
//

import Foundation
import SwiftData

@Model
final class Site {
    @Attribute(.unique) var name: String
    var notes: String?
    var isPrimaryPad: Bool
    var gridColumns: Int?
    var gridRows: Int?

    init(
        name: String,
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

func seedDefaultSites(context: ModelContext) {
    context.insert(
        Site(
            name: "Bennett Valley",
            notes: "Bennett Valley Test Site",
            isPrimaryPad: true,
            gridColumns: 12,
            gridRows: 50
        )
    )
}
