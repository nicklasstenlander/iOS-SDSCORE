import CallKit
import Foundation

final class CallDirectoryHandler: CXCallDirectoryProvider, CXCallDirectoryExtensionContextDelegate {
    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self

        for entry in Self.loadEntries() {
            context.addIdentificationEntry(
                withNextSequentialPhoneNumber: CXCallDirectoryPhoneNumber(entry.phoneNumber),
                label: entry.label
            )
        }

        context.completeRequest()
    }

    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext, withError error: Error) {
        NSLog("CORECallDirectory request failed: %@", error.localizedDescription)
    }

    private static func loadEntries() -> [Entry] {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.se.sollentunadansochscenskola.core")?
            .appendingPathComponent("call-directory-identifications.json", isDirectory: false),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }

        var seen = Set<Int64>()
        return entries
            .sorted { $0.phoneNumber < $1.phoneNumber }
            .filter { entry in
                guard !seen.contains(entry.phoneNumber) else { return false }
                seen.insert(entry.phoneNumber)
                return true
            }
    }
}

private struct Entry: Codable {
    let phoneNumber: Int64
    let label: String
}
