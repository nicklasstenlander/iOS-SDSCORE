import Foundation

enum Periods {
    static let eventBlockIdsByCode: [String: String] = [
        "VT26": "18402",
        "HT26": "19459"
    ]

    static func defaultEventBlockId(date: Date = Date()) -> String {
        let year = Calendar.current.component(.year, from: date) % 100
        let month = Calendar.current.component(.month, from: date)
        let term = month < 7 ? "VT" : "HT"
        return eventBlockIdsByCode[String(format: "%@%02d", term, year)] ?? ""
    }

    static func defaultFullPeriodLabel(date: Date = Date()) -> String {
        let year = Calendar.current.component(.year, from: date)
        let month = Calendar.current.component(.month, from: date)
        return month < 7 ? "Vårterminen \(year)" : "Höstterminen \(year)"
    }

    static func blockNameToCode(_ name: String) -> String {
        if let year = firstYear(in: name, prefixes: ["Höst", "Hösten", "höst", "hösten"]) {
            return "HT\(String(year.suffix(2)))"
        }

        if let year = firstYear(in: name, prefixes: ["Vår", "Våren", "vår", "våren"]) {
            return "VT\(String(year.suffix(2)))"
        }

        return name
    }

    static func blockNameToFullLabel(_ name: String) -> String {
        if let year = firstYear(in: name, prefixes: ["Höst", "Hösten", "höst", "hösten"]) {
            return "Höstterminen \(year)"
        }

        if let year = firstYear(in: name, prefixes: ["Vår", "Våren", "vår", "våren"]) {
            return "Vårterminen \(year)"
        }

        return name
    }

    static func codeToLabel(_ code: String) -> String {
        guard code.count == 4 else { return code }
        let term = String(code.prefix(2))
        let year = String(code.suffix(2))
        guard term == "HT" || term == "VT", Int(year) != nil else { return code }
        return "\(term) 20\(year)"
    }

    static func isPeriodCode(_ value: String) -> Bool {
        value.range(of: #"^(HT|VT)\d{2}$"#, options: .regularExpression) != nil
    }

    static func dateToPeriodCode(_ date: String?) -> String {
        guard let date, date.count >= 7 else { return "" }
        let year = String(date.prefix(4))
        let monthText = String(date.dropFirst(5).prefix(2))
        guard year.range(of: #"^\d{4}$"#, options: .regularExpression) != nil,
              let month = Int(monthText) else { return "" }
        return "\(month >= 7 ? "HT" : "VT")\(year.suffix(2))"
    }

    static func matchesPeriodCode(_ code: String, values: [String?]) -> Bool {
        let normalizedCode = code.uppercased()
        return values.contains { value in
            guard let value else { return false }
            let normalizedValue = value.uppercased()
            return normalizedValue.contains(normalizedCode) || dateToPeriodCode(value) == normalizedCode
        }
    }

    static func sortPeriodCodes(_ codes: [String]) -> [String] {
        codes.sorted { lhs, rhs in
            guard let left = parsePeriod(lhs), let right = parsePeriod(rhs) else { return lhs > rhs }
            if left.year != right.year { return left.year > right.year }
            return left.term > right.term
        }
    }

    private static func parsePeriod(_ code: String) -> (term: String, year: Int)? {
        guard isPeriodCode(code) else { return nil }
        let term = String(code.prefix(2))
        let year = Int(code.suffix(2)) ?? 0
        return (term, year)
    }

    private static func firstYear(in value: String, prefixes: [String]) -> String? {
        for prefix in prefixes {
            let pattern = #"\#(prefix)\s+(\d{4})"#
            if let range = value.range(of: pattern, options: .regularExpression) {
                let match = String(value[range])
                return match.split(separator: " ").last.map(String.init)
            }
        }

        return nil
    }
}
