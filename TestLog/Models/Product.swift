//
//  Product.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//

import Foundation
import SwiftData

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
