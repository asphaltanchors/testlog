//
//  Enums.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//

import Foundation

// MARK: - Product Category

enum ProductCategory: String, Codable, CaseIterable, Identifiable {
    case anchor = "Anchor"
    case adhesive = "Adhesive"

    var id: String { rawValue }
}

// MARK: - Anchor Material

enum AnchorMaterial: String, Codable, CaseIterable, Identifiable {
    case zinc = "Zinc"
    case stainless = "Stainless"

    var id: String { rawValue }
}

// MARK: - Hole Diameter

enum HoleDiameter: String, Codable, CaseIterable, Identifiable {
    case sevenEighths = "7/8\""
    case oneAndOneEighth = "1.125\""
    case oneAndOneQuarter = "1.25\""
    case oneAndOneHalf = "1.5\""

    var id: String { rawValue }
}

// MARK: - Brushed Status

enum BrushedStatus: String, Codable, CaseIterable, Identifiable {
    case yes = "Y"
    case no = "N"
    case partial = "Partial"

    var id: String { rawValue }
}

// MARK: - Test Type

enum TestType: String, Codable, CaseIterable, Identifiable {
    case pull = "Pull"

    var id: String { rawValue }
}

// MARK: - Failure Mode

enum FailureMode: String, Codable, CaseIterable, Identifiable {
    case cleanPull = "Clean Pull"
    case snappedHead = "Snapped Head"
    case headPoppedOff = "Head Popped Off"
    case partial = "Partial"

    var id: String { rawValue }
}

// MARK: - Mix Consistency

enum MixConsistency: String, Codable, CaseIterable, Identifiable {
    case thin = "Thin"
    case standard = "Standard"
    case thick = "Thick"
    case wateredDown = "Watered Down"

    var id: String { rawValue }
}

// MARK: - Test Status

enum TestStatus: String, Codable, CaseIterable, Identifiable {
    case planned = "Planned"
    case installed = "Installed"
    case completed = "Completed"
    case invalid = "Invalid"
    case partial = "Partial"

    var id: String { rawValue }
}

// MARK: - Asset Type

enum AssetType: String, Codable, CaseIterable, Identifiable {
    case video = "Video"
    case photo = "Photo"
    case export = "Export"
    case document = "Document"

    var id: String { rawValue }
}
