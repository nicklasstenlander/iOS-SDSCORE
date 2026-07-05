import CoreText
import Foundation
import UIKit

enum FontRegistrar {
    @MainActor
    static func registerAgrandirFonts() {
        let fontURLs = [
            "Agrandir-GrandLight",
            "Agrandir-Regular",
            "Agrandir-TextBold"
        ].compactMap(fontURL)

        guard !fontURLs.isEmpty else { return }

        CTFontManagerRegisterFontURLs(fontURLs as CFArray, .process, true) { _, _ in
            true
        }
    }

    private static func fontURL(for assetName: String) -> URL? {
        guard let asset = NSDataAsset(name: assetName) else { return nil }

        let directory = FileManager.default.temporaryDirectory.appending(path: "AgrandirFonts", directoryHint: .isDirectory)
        let url = directory.appending(path: "\(assetName).otf")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            if !FileManager.default.fileExists(atPath: url.path) {
                try asset.data.write(to: url, options: .atomic)
            }

            return url
        } catch {
            return nil
        }
    }
}
