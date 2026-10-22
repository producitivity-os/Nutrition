import Foundation

struct NutrientTablePasteRow: Equatable {
    var nutrientName: String?
    var amount: String
    var unit: String?
}

enum NutrientTablePasteParser {
    static func rows(from source: String) -> [NutrientTablePasteRow] {
        let matrix = parseMatrix(source)
        guard !matrix.isEmpty else { return [] }

        let header = columnMapping(for: matrix[0])
        if header.isHeader {
            return matrix.dropFirst().compactMap { row in
                makeRow(row, nameColumn: header.name, amountColumn: header.amount, unitColumn: header.unit)
            }
        }

        let namedRows = matrix.compactMap { row -> NutrientTablePasteRow? in
            guard row.count >= 2,
                  normalizedAmount(row[0]) == nil,
                  let amountColumn = row.indices.dropFirst().first(where: { normalizedAmount(row[$0]) != nil }) else {
                return nil
            }
            return makeRow(
                row,
                nameColumn: 0,
                amountColumn: amountColumn,
                unitColumn: amountColumn + 1 < row.count ? amountColumn + 1 : nil
            )
        }
        if namedRows.count == matrix.count { return namedRows }

        return matrix.flatMap { row in
            row.compactMap { cell in
                guard let amount = normalizedAmount(cell) else { return nil }
                return NutrientTablePasteRow(nutrientName: nil, amount: amount, unit: nil)
            }
        }
    }

    static func normalizedName(_ source: String) -> String {
        source
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
    }

    private static func makeRow(
        _ cells: [String],
        nameColumn: Int?,
        amountColumn: Int?,
        unitColumn: Int?
    ) -> NutrientTablePasteRow? {
        guard let amountColumn,
              cells.indices.contains(amountColumn),
              let amount = normalizedAmount(cells[amountColumn]) else { return nil }
        let name = nameColumn.flatMap { cells.indices.contains($0) ? cleaned(cells[$0]) : nil }
        let unit = unitColumn.flatMap { cells.indices.contains($0) ? cleaned(cells[$0]) : nil }
        return NutrientTablePasteRow(
            nutrientName: name?.isEmpty == false ? name : nil,
            amount: amount,
            unit: unit?.isEmpty == false ? unit : nil
        )
    }

    private static func columnMapping(for row: [String]) -> (isHeader: Bool, name: Int?, amount: Int?, unit: Int?) {
        var name: Int?
        var amount: Int?
        var unit: Int?
        var headerMatches = 0
        for (index, cell) in row.enumerated() {
            let value = normalizedName(cell)
            if ["nutrient", "nutrientname", "name"].contains(value) {
                name = index
                headerMatches += 1
            } else if ["amount", "value", "quantity", "per100g", "per100ml"].contains(value) {
                amount = index
                headerMatches += 1
            } else if ["unit", "units"].contains(value) {
                unit = index
                headerMatches += 1
            } else if ["category", "status"].contains(value) {
                headerMatches += 1
            }
        }
        return (headerMatches > 0 && amount != nil, name, amount, unit)
    }

    private static func parseMatrix(_ source: String) -> [[String]] {
        source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") }
            .map(parseLine)
            .filter { !$0.isEmpty && !isMarkdownSeparator($0) }
    }

    private static func parseLine(_ source: String) -> [String] {
        let line = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.contains("\t") {
            return line.split(separator: "\t", omittingEmptySubsequences: false).map { cleaned(String($0)) }
        }
        if line.contains("|") {
            var cells = splitDelimited(line, delimiter: "|")
            if cells.first?.isEmpty == true { cells.removeFirst() }
            if cells.last?.isEmpty == true { cells.removeLast() }
            return cells
        }
        if line.contains(";") { return splitDelimited(line, delimiter: ";") }
        if line.contains(",") { return splitDelimited(line, delimiter: ",") }
        let whitespaceSeparated = line
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
        if whitespaceSeparated.count > 1,
           whitespaceSeparated.allSatisfy({ normalizedAmount($0) != nil }) {
            return whitespaceSeparated.map(cleaned)
        }
        return [cleaned(line)]
    }

    private static func splitDelimited(_ source: String, delimiter: Character) -> [String] {
        var cells: [String] = []
        var cell = ""
        var quoted = false
        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]
            if character == "\"" {
                let next = source.index(after: index)
                if quoted, next < source.endIndex, source[next] == "\"" {
                    cell.append("\"")
                    index = source.index(after: next)
                    continue
                }
                quoted.toggle()
            } else if character == delimiter, !quoted {
                cells.append(cleaned(cell))
                cell = ""
            } else {
                cell.append(character)
            }
            index = source.index(after: index)
        }
        cells.append(cleaned(cell))
        return cells
    }

    private static func normalizedAmount(_ source: String) -> String? {
        let value = cleaned(source)
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "–", with: "-")
        guard !value.isEmpty else { return nil }
        if value.caseInsensitiveCompare("unknown") == .orderedSame { return "0" }
        guard !["—", "-", "n/a", "na", "null"].contains(value.lowercased()) else { return nil }

        let numericSource = value.trimmingCharacters(
            in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "~≈<>≤≥"))
        )
        let pattern = #"^[-+]?(?:\d+(?:[.,]\d*)?|[.,]\d+)(?:[eE][-+]?\d+)?"#
        guard let range = numericSource.range(of: pattern, options: .regularExpression) else { return nil }
        var number = String(numericSource[range])
        if number.contains(","), number.contains(".") {
            number.removeAll { $0 == "," }
        } else if number.contains(",") {
            let parts = number.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count == 2, parts[1].count <= 2 {
                number = number.replacingOccurrences(of: ",", with: ".")
            } else {
                number.removeAll { $0 == "," }
            }
        }
        guard let parsed = Double(number), parsed >= 0 else { return nil }
        let portable = String(parsed)
        return portable.hasSuffix(".0") ? String(portable.dropLast(2)) : portable
    }

    private static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"")))
    }

    private static func isMarkdownSeparator(_ row: [String]) -> Bool {
        guard !row.isEmpty else { return false }
        return row.allSatisfy { cell in
            let value = cell.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { return true }
            return value.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }
}
