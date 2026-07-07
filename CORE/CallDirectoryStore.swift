import Foundation

#if canImport(CallKit) && os(iOS)
import CallKit
#endif

struct CallDirectoryEntry: Codable, Hashable {
    let phoneNumber: Int64
    let label: String
}

enum CORECallDirectoryStore {
    static let appGroupIdentifier = "group.se.sollentunadansochscenskola.core"
    static let entriesFileName = "call-directory-identifications.json"
    static let extensionIdentifier = "SDS.CORE.CORECallDirectory"

    static func writeEntries(from bookings: [Booking]) throws -> Int {
        let entries = entries(from: bookings)
        guard let url = entriesURL else {
            throw CallDirectoryStoreError.missingAppGroup
        }
        let data = try JSONEncoder().encode(entries)
        try data.write(to: url, options: [.atomic])
        return entries.count
    }

    static func entries(from bookings: [Booking]) -> [CallDirectoryEntry] {
        var labelsByNumber: [Int64: String] = [:]

        for booking in bookings {
            let name = booking.participant?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }

            for phone in SDSPhoneNumbers.participantPhoneNumbers(in: booking) {
                guard let number = SDSPhoneNumbers.e164Digits(phone), labelsByNumber[number] == nil else { continue }
                labelsByNumber[number] = "\(name) · SODSS"
            }
        }

        return labelsByNumber
            .map { CallDirectoryEntry(phoneNumber: $0.key, label: $0.value) }
            .sorted { $0.phoneNumber < $1.phoneNumber }
    }

    static func reloadExtension() async throws {
        #if canImport(CallKit) && os(iOS)
        try await CXCallDirectoryManager.sharedInstance.reloadExtension(withIdentifier: extensionIdentifier)
        #else
        throw CallDirectoryStoreError.unsupportedPlatform
        #endif
    }

    static var entriesURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(entriesFileName, isDirectory: false)
    }
}

enum CallDirectoryStoreError: LocalizedError {
    case missingAppGroup
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case .missingAppGroup:
            "App Group-container saknas. Kontrollera att App Groups är aktiverat för app och extension."
        case .unsupportedPlatform:
            "Nummerpresentation kan bara uppdateras på iPhone."
        }
    }
}
