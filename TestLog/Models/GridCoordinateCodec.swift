import Foundation

enum GridCoordinateCodec {
    static func normalizedGridColumnOrNil(_ value: String) -> String? {
        let compact = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
        return compact.isEmpty ? nil : compact
    }

    static func gridColumnIndex(from value: String?) -> Int? {
        guard let normalized = normalizedGridColumnOrNil(value ?? "") else { return nil }

        if let numeric = Int(normalized), numeric > 0 {
            return numeric
        }

        let uppercased = normalized.uppercased()
        guard uppercased.allSatisfy(\.isLetter) else { return nil }

        var result = 0
        for scalar in uppercased.unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else { return nil }
            result = result * 26 + Int(scalar.value - 64)
        }
        return result > 0 ? result : nil
    }

    static func validGridRow(_ row: Int?) -> Int? {
        guard let row, row > 0 else { return nil }
        return row
    }

    static func gridColumnLabel(for index: Int) -> String {
        guard index > 0 else { return "?" }

        var value = index
        var characters: [Character] = []
        while value > 0 {
            let remainder = (value - 1) % 26
            guard let scalar = UnicodeScalar(65 + remainder) else { break }
            characters.append(Character(scalar))
            value = (value - 1) / 26
        }
        return String(characters.reversed())
    }

    static func coordinateLabel(column: String?, row: Int?) -> String? {
        guard
            let columnIndex = gridColumnIndex(from: column),
            let validRow = validGridRow(row)
        else {
            return nil
        }
        return "\(gridColumnLabel(for: columnIndex))\(validRow)"
    }

    static func coordinateKey(column: String?, row: Int?) -> String? {
        guard
            let columnIndex = gridColumnIndex(from: column),
            let validRow = validGridRow(row)
        else {
            return nil
        }
        return "\(columnIndex)-\(validRow)"
    }
}
