import Foundation

enum GridCoordinateCodec {
    static func gridColumnIndex(from value: String?) -> Int? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
        guard !normalized.isEmpty else { return nil }

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

    static func validGridColumn(_ column: Int?) -> Int? {
        guard let column, column > 0 else { return nil }
        return column
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

    static func coordinateLabel(column: Int?, row: Int?) -> String? {
        guard
            let columnIndex = validGridColumn(column),
            let validRow = validGridRow(row)
        else {
            return nil
        }
        return "\(gridColumnLabel(for: columnIndex))\(validRow)"
    }

    static func coordinateKey(column: Int?, row: Int?) -> String? {
        guard
            let columnIndex = validGridColumn(column),
            let validRow = validGridRow(row)
        else {
            return nil
        }
        return "\(columnIndex)-\(validRow)"
    }
}
