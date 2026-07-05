import Foundation

enum BookingStatusFormatter {
    private static let labels: [String: String] = [
        "ACCEPTED": "Accepterad",
        "ACCEPTED_ON_PAYMENT": "Inväntar betalning",
        "AWAITING_FEE": "Inväntar betalning",
        "NEW": "Inväntar handläggning",
        "IN_QUEUE": "Köplats",
        "AWAITING_RESPONSE": "Inväntar svar",
        "WAITING": "Väntar",
        "Accepted": "Accepterad",
        "Accepted on payment": "Inväntar betalning",
        "To be processed": "Inväntar handläggning"
    ]

    static func format(code raw: String?, fallback fallbackRaw: String? = nil) -> String {
        guard let raw, !raw.isEmpty else { return "—" }

        let queueSource = raw == "IN_QUEUE" ? fallbackRaw : raw
        if let queueSource,
           let range = queueSource.range(of: #"^Queue position\s+(\d+)$"#, options: [.regularExpression, .caseInsensitive]) {
            let matched = String(queueSource[range])
            let position = matched.split(separator: " ").last.map(String.init) ?? ""
            return "Köplats \(position)"
        }

        if let label = labels[raw] { return label }
        if let fallbackRaw, let label = labels[fallbackRaw] { return label }
        return raw
    }
}
