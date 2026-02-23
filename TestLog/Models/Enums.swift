//
//  Enums.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//

import Foundation

// MARK: - Product Category

enum ProductCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case anchor = "Anchor"
    case adhesive = "Adhesive"

    var id: String { rawValue }
}

// MARK: - Anchor Material

enum AnchorMaterial: String, Codable, CaseIterable, Identifiable {
    case zinc = "Zinc"
    case stainless = "Stainless"
    case plastic = "Plastic"

    var id: String { rawValue }
}

// MARK: - Hole Diameter

enum HoleDiameter: String, Codable, CaseIterable, Identifiable {
    case threeQuarters = "3/4\""
    case sevenEighths = "7/8\""
    case one = "1\""
    case oneAndOneEighth = "1 - 1/8\""
    case oneAndOneQuarter = "1 - 1/4\""
    case oneAndThreeEighths = "1 - 3/8\""
    case oneAndOneHalf = "1 - 1/2\""

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        if let parsed = HoleDiameter(rawValue: value) {
            self = parsed
            return
        }

        // Backward compatibility for previously stored decimal-style values.
        switch value {
        case "1.125\"":
            self = .oneAndOneEighth
        case "1.25\"":
            self = .oneAndOneQuarter
        case "1.375\"":
            self = .oneAndThreeEighths
        case "1.5\"":
            self = .oneAndOneHalf
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid hole diameter: \(value)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Brush Size

enum BrushSize: String, Codable, CaseIterable, Identifiable {
    case none = "None"
    case undersized = "Undersized"
    case matched = "Matched"
    case oversized = "Oversized"

    var id: String { rawValue }
}

// MARK: - Test Type

enum TestType: String, Codable, CaseIterable, Identifiable {
    case pull = "Pull"
    case shear = "Shear"

    var id: String { rawValue }
}

// MARK: - Measurement Type

enum MeasurementType: String, Codable, CaseIterable, Identifiable {
    case observedPeak = "Observed Peak"
    case testerPeak = "Tester Peak"

    var id: String { rawValue }
}

// MARK: - Failure Mode

// Single-field failure mode retained to support older data formats.
enum FailureMode: String, Codable, CaseIterable, Identifiable {
    case cleanPull = "Clean Pull"
    case snappedHead = "Snapped Head"
    case headPoppedOff = "Head Popped Off"
    case partial = "Partial"

    var id: String { rawValue }
}

// MARK: - Failure Family

enum FailureFamily: String, Codable, CaseIterable, Identifiable {
    case anchorStructural = "Anchor Structural Failure"
    case bondPullout = "Bond Pullout"
    case equipmentFailure = "Equipment Failure"
    case other = "Other"

    var id: String { rawValue }

    static func options(for testType: TestType?) -> [FailureFamily] {
        switch testType {
        case .shear:
            return [.anchorStructural, .bondPullout, .equipmentFailure, .other]
        case .pull, nil:
            return [.anchorStructural, .bondPullout, .other]
        }
    }
}

// MARK: - Failure Mechanism

enum FailureMechanism: String, Codable, CaseIterable, Identifiable {
    case headWasherInterface = "Head/Washer Interface Failure"
    case shankMaterialFracture = "Shank Material Fracture"
    case progressivePullout = "Progressive Pullout"
    case fixtureFailure = "Fixture Failure"
    case loadCellIssue = "Load Cell Issue"
    case otherEquipment = "Other Equipment Failure"

    var id: String { rawValue }

    static func options(for testType: TestType?, family: FailureFamily?) -> [FailureMechanism] {
        guard let family else { return [] }

        switch family {
        case .anchorStructural:
            return [.headWasherInterface, .shankMaterialFracture]
        case .bondPullout:
            return [.progressivePullout]
        case .equipmentFailure:
            if testType == .shear {
                return [.fixtureFailure, .loadCellIssue, .otherEquipment]
            }
            return []
        case .other:
            return []
        }
    }
}

// MARK: - Failure Behavior

enum FailureBehavior: String, Codable, CaseIterable, Identifiable {
    case catastrophic = "Catastrophic"
    case progressive = "Progressive"

    var id: String { rawValue }

    static func options(for family: FailureFamily?) -> [FailureBehavior] {
        switch family {
        case .anchorStructural:
            return [.catastrophic]
        case .bondPullout:
            return [.progressive]
        case .equipmentFailure:
            return [.catastrophic, .progressive]
        case .other:
            return [.catastrophic, .progressive]
        case nil:
            return []
        }
    }
}

// MARK: - Test Status

enum TestStatus: String, Codable, CaseIterable, Identifiable {
    case planned = "Planned"
    case installed = "Installed"
    case completed = "Completed"

    var id: String { rawValue }
}

// MARK: - Asset Type

enum AssetType: String, Codable, CaseIterable, Identifiable {
    case video = "Video"
    case photo = "Photo"
    case export = "Export"
    case document = "Document"
    case testerData = "Tester Data"

    var id: String { rawValue }
}

// MARK: - Video Role

enum VideoRole: String, Codable, CaseIterable, Identifiable {
    case anchorView = "Anchor View"
    case equipmentView = "Equipment View"
    case unassigned = "Unassigned"

    var id: String { rawValue }
}
