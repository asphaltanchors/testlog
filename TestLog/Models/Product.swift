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
    @Attribute(.unique) var sku: String
    var displayName: String
    var category: ProductCategory
    var notes: String?

    @Relationship(inverse: \PullTest.product)
    var tests: [PullTest] = []

    @Relationship(inverse: \PullTest.adhesive)
    var adhesiveTests: [PullTest] = []

    init(sku: String, displayName: String, category: ProductCategory = .anchor, notes: String? = nil) {
        self.sku = sku
        self.displayName = displayName
        self.category = category
        self.notes = notes
    }
}
