import Foundation
import SwiftData

@MainActor
struct TestCSVImportService {
    struct ImportReport {
        let totalRows: Int
        let createdCount: Int
        let updatedCount: Int
        let skippedCount: Int
        let warnings: [String]

        var summary: String {
            var lines: [String] = [
                "Processed \(totalRows) row(s).",
                "Created: \(createdCount)",
                "Updated: \(updatedCount)",
                "Skipped: \(skippedCount)",
            ]
            if !warnings.isEmpty {
                lines.append("")
                lines.append(contentsOf: warnings)
            }
            return lines.joined(separator: "\n")
        }
    }

    enum ImportError: LocalizedError {
        case unreadableFile
        case missingHeader(String)
        case emptyFile

        var errorDescription: String? {
            switch self {
            case .unreadableFile:
                return "Could not read the CSV file."
            case .missingHeader(let name):
                return "Missing required CSV column: \(name)"
            case .emptyFile:
                return "The CSV file is empty."
            }
        }
    }

    func importCSV(from url: URL, into modelContext: ModelContext) throws -> ImportReport {
        let fileData = try Data(contentsOf: url)
        guard
            let rawText = String(data: fileData, encoding: .utf8)
                ?? String(data: fileData, encoding: .utf16)
                ?? String(data: fileData, encoding: .unicode)
        else {
            throw ImportError.unreadableFile
        }

        let rows = parseCSVRows(rawText)
        guard let headerRow = rows.first else {
            throw ImportError.emptyFile
        }

        let headerIndex = Dictionary(uniqueKeysWithValues: headerRow.enumerated().map { index, header in
            (normalizedHeader(header), index)
        })

        let requiredHeaders = [
            "Test ID": "testid",
            "Installed Date": "installeddate",
            "Tested Date": "testeddate",
            "Product": "product",
            "Material": "material",
            "Adhesive": "adhesive",
            "Test Type": "testtype",
            "Pavement Temp": "pavementtemp",
        ]

        for (displayName, key) in requiredHeaders {
            if headerIndex[key] == nil {
                throw ImportError.missingHeader(displayName)
            }
        }

        let allTests = try modelContext.fetch(FetchDescriptor<PullTest>())
        let allProducts = try modelContext.fetch(FetchDescriptor<Product>())
        let allSites = try modelContext.fetch(FetchDescriptor<Site>())

        let defaultSite = allSites.first(where: \.isPrimaryPad) ?? allSites.first
        let existingByTestID = Dictionary(
            allTests.compactMap { test -> (String, PullTest)? in
                guard let testID = trimmedOrNil(test.testID) else { return nil }
                return (testID.lowercased(), test)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let anchorProducts = allProducts.filter { $0.category == .anchor }
        let adhesiveProducts = allProducts.filter { $0.category == .adhesive }
        let cutMarkerName = "CUT"
        let sp18ProductName = "SP18"
        let cutDownSP18Note = "Cut-down SP18 test."
        var sp18Product = anchorProducts.first {
            $0.name.caseInsensitiveCompare(sp18ProductName) == .orderedSame
        }
        if sp18Product == nil {
            let product = Product(name: sp18ProductName, category: .anchor)
            modelContext.insert(product)
            sp18Product = product
        }

        var created = 0
        var updated = 0
        var skipped = 0
        var rowsWithInvalidInstalledDate = 0
        var rowsWithInvalidTestedDate = 0
        var rowsWithInvalidTemp = 0
        var rowsWithInvalidLocation = 0
        var unmatchedAnchorNames = Set<String>()
        var unmatchedAdhesiveNames = Set<String>()
        var unmatchedMaterials = Set<String>()
        var unmatchedTestTypes = Set<String>()

        let installedDateColumn = headerIndex["installeddate"]!
        let testedDateColumn = headerIndex["testeddate"]!
        let testIDColumn = headerIndex["testid"]!
        let productColumn = headerIndex["product"]!
        let materialColumn = headerIndex["material"]!
        let adhesiveColumn = headerIndex["adhesive"]!
        let testTypeColumn = headerIndex["testtype"]!
        let pavementTempColumn = headerIndex["pavementtemp"]!
        let locationColumn = headerIndex["location"]

        for row in rows.dropFirst() {
            let testID = value(in: row, at: testIDColumn)
            guard let normalizedTestID = trimmedOrNil(testID) else {
                skipped += 1
                continue
            }

            let installedDateRaw = value(in: row, at: installedDateColumn)
            let testedDateRaw = value(in: row, at: testedDateColumn)
            let productRaw = value(in: row, at: productColumn)
            let materialRaw = value(in: row, at: materialColumn)
            let adhesiveRaw = value(in: row, at: adhesiveColumn)
            let testTypeRaw = value(in: row, at: testTypeColumn)
            let pavementTempRaw = value(in: row, at: pavementTempColumn)
            let locationRaw = locationColumn.map { value(in: row, at: $0) } ?? ""

            let installedDate = parseDate(installedDateRaw)
            let testedDate = parseDate(testedDateRaw)
            let pavementTemp = parseInteger(pavementTempRaw)
            let locationCoordinate = parseLocationCoordinate(locationRaw)
            let isCutProductRow = trimmedOrNil(productRaw)?
                .caseInsensitiveCompare(cutMarkerName) == .orderedSame

            if trimmedOrNil(installedDateRaw) != nil && installedDate == nil {
                rowsWithInvalidInstalledDate += 1
            }
            if trimmedOrNil(testedDateRaw) != nil && testedDate == nil {
                rowsWithInvalidTestedDate += 1
            }
            if trimmedOrNil(pavementTempRaw) != nil && pavementTemp == nil {
                rowsWithInvalidTemp += 1
            }
            if trimmedOrNil(locationRaw) != nil && locationCoordinate == nil {
                rowsWithInvalidLocation += 1
            }

            let matchedProduct = isCutProductRow ? sp18Product : matchProduct(named: productRaw, in: anchorProducts)
            if trimmedOrNil(productRaw) != nil, matchedProduct == nil {
                unmatchedAnchorNames.insert(productRaw.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            let matchedAdhesive = matchProduct(named: adhesiveRaw, in: adhesiveProducts)
            if trimmedOrNil(adhesiveRaw) != nil, matchedAdhesive == nil {
                unmatchedAdhesiveNames.insert(adhesiveRaw.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            let matchedMaterial = parseAnchorMaterial(materialRaw)
            if trimmedOrNil(materialRaw) != nil, matchedMaterial == nil {
                unmatchedMaterials.insert(materialRaw.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            let matchedTestType = parseTestType(testTypeRaw)
            if trimmedOrNil(testTypeRaw) != nil, matchedTestType == nil {
                unmatchedTestTypes.insert(testTypeRaw.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            if let existing = existingByTestID[normalizedTestID.lowercased()] {
                existing.testID = normalizedTestID
                existing.product = matchedProduct
                existing.installedDate = installedDate
                existing.testedDate = testedDate
                existing.anchorMaterial = matchedMaterial
                existing.adhesive = matchedAdhesive
                existing.testType = matchedTestType ?? .pull
                existing.pavementTemp = pavementTemp
                if isCutProductRow {
                    existing.isValid = false
                    existing.notes = appendedNote(existing.notes, note: cutDownSP18Note)
                }
                if let locationCoordinate {
                    let location = existing.location ?? Location()
                    location.site = existing.site ?? defaultSite
                    location.gridColumn = locationCoordinate.column
                    location.gridRow = locationCoordinate.row
                    if existing.location == nil {
                        existing.location = location
                    }
                } else if trimmedOrNil(locationRaw) == nil {
                    existing.location = nil
                }
                updated += 1
            } else {
                let test = PullTest(
                    testID: normalizedTestID,
                    product: matchedProduct,
                    site: defaultSite,
                    installedDate: installedDate,
                    testedDate: testedDate,
                    anchorMaterial: matchedMaterial,
                    adhesive: matchedAdhesive,
                    pavementTemp: pavementTemp,
                    testType: matchedTestType ?? .pull
                )
                if isCutProductRow {
                    test.isValid = false
                    test.notes = cutDownSP18Note
                }
                if let locationCoordinate {
                    test.location = Location(
                        site: test.site ?? defaultSite,
                        gridColumn: locationCoordinate.column,
                        gridRow: locationCoordinate.row
                    )
                }
                modelContext.insert(test)
                created += 1
            }
        }

        try modelContext.save()

        var warnings: [String] = []
        if rowsWithInvalidInstalledDate > 0 {
            warnings.append("Invalid Installed Date rows: \(rowsWithInvalidInstalledDate)")
        }
        if rowsWithInvalidTestedDate > 0 {
            warnings.append("Invalid Tested Date rows: \(rowsWithInvalidTestedDate)")
        }
        if rowsWithInvalidTemp > 0 {
            warnings.append("Invalid Pavement Temp rows: \(rowsWithInvalidTemp)")
        }
        if rowsWithInvalidLocation > 0 {
            warnings.append("Invalid Location rows: \(rowsWithInvalidLocation)")
        }
        if !unmatchedAnchorNames.isEmpty {
            warnings.append("Unmatched anchor products: \(unmatchedAnchorNames.sorted().joined(separator: ", "))")
        }
        if !unmatchedAdhesiveNames.isEmpty {
            warnings.append("Unmatched adhesives: \(unmatchedAdhesiveNames.sorted().joined(separator: ", "))")
        }
        if !unmatchedMaterials.isEmpty {
            warnings.append("Unmatched materials: \(unmatchedMaterials.sorted().joined(separator: ", "))")
        }
        if !unmatchedTestTypes.isEmpty {
            warnings.append("Unmatched test types: \(unmatchedTestTypes.sorted().joined(separator: ", "))")
        }

        return ImportReport(
            totalRows: rows.count - 1,
            createdCount: created,
            updatedCount: updated,
            skippedCount: skipped,
            warnings: warnings
        )
    }

    private func value(in row: [String], at index: Int) -> String {
        guard index >= 0, index < row.count else { return "" }
        return row[index]
    }

    private func normalizedHeader(_ value: String) -> String {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
            .lowercased()
        return String(trimmed.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    private func trimmedOrNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseDate(_ rawValue: String) -> Date? {
        guard let trimmed = trimmedOrNil(rawValue) else { return nil }
        let formats = ["M/d/yyyy", "MM/dd/yyyy", "yyyy-MM-dd"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    private func appendedNote(_ existing: String?, note: String) -> String {
        guard let existing = trimmedOrNil(existing) else { return note }
        if existing.localizedCaseInsensitiveContains(note) {
            return existing
        }
        return "\(existing)\n\(note)"
    }

    private func parseInteger(_ rawValue: String) -> Int? {
        guard let trimmed = trimmedOrNil(rawValue) else { return nil }
        if let integer = Int(trimmed) {
            return integer
        }
        if let decimal = Double(trimmed), decimal.isFinite {
            return Int(decimal.rounded())
        }
        return nil
    }

    private func parseLocationCoordinate(_ rawValue: String) -> (column: Int, row: Int)? {
        guard let trimmed = trimmedOrNil(rawValue) else { return nil }
        let compact = trimmed
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
        guard !compact.isEmpty else { return nil }

        let prefixLetters = String(compact.prefix { $0.isLetter })
        let suffixDigits = String(compact.dropFirst(prefixLetters.count))
        guard !prefixLetters.isEmpty, !suffixDigits.isEmpty else { return nil }
        guard suffixDigits.allSatisfy(\.isNumber), let row = Int(suffixDigits), row > 0 else { return nil }
        guard let column = GridCoordinateCodec.gridColumnIndex(from: prefixLetters) else { return nil }
        return (column: column, row: row)
    }

    private func parseAnchorMaterial(_ rawValue: String) -> AnchorMaterial? {
        guard let trimmed = trimmedOrNil(rawValue) else { return nil }
        return AnchorMaterial.allCases.first {
            $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    private func parseTestType(_ rawValue: String) -> TestType? {
        guard let trimmed = trimmedOrNil(rawValue) else { return nil }
        return TestType.allCases.first {
            $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    private func matchProduct(named rawName: String, in products: [Product]) -> Product? {
        guard let rawName = trimmedOrNil(rawName) else { return nil }
        let query = normalizedSearchText(rawName)
        guard !query.isEmpty else { return nil }

        if let exactMatch = products.first(where: { normalizedSearchText($0.name) == query }) {
            return exactMatch
        }

        return products.first { product in
            let candidate = normalizedSearchText(product.name)
            return candidate.contains(query) || query.contains(candidate)
        }
    }

    private func normalizedSearchText(_ value: String) -> String {
        value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private func parseCSVRows(_ text: String) -> [[String]] {
        let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var isInsideQuotes = false

        let characters = Array(normalizedText)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                let nextIsEscapedQuote = isInsideQuotes && (index + 1 < characters.count) && characters[index + 1] == "\""
                if nextIsEscapedQuote {
                    currentField.append("\"")
                    index += 2
                    continue
                }
                isInsideQuotes.toggle()
            } else if character == "," && !isInsideQuotes {
                currentRow.append(currentField)
                currentField = ""
            } else if character == "\n" && !isInsideQuotes {
                currentRow.append(currentField)
                if !currentRow.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    rows.append(currentRow)
                }
                currentRow = []
                currentField = ""
            } else {
                currentField.append(character)
            }
            index += 1
        }

        currentRow.append(currentField)
        if !currentRow.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            rows.append(currentRow)
        }
        return rows
    }
}
