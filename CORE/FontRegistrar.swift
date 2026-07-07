import CoreText
import Foundation
import UIKit

enum FontRegistrar {
    private static var didRegisterAgrandirFonts = false

    static func registerAgrandirFonts() {
        guard !didRegisterAgrandirFonts else { return }
        didRegisterAgrandirFonts = true

        let fontNames = [
            "Agrandir-GrandHeavy",
            "Agrandir-GrandLight",
            "Agrandir-Narrow",
            "Agrandir-Regular",
            "Agrandir-TextBold",
            "Agrandir-ThinItalic",
            "Agrandir-Tight",
            "Agrandir-WideBlackItalic",
            "Agrandir-WideLight"
        ]
        let fontURLs = fontNames.compactMap(fontURL)

        guard !fontURLs.isEmpty else { return }

        CTFontManagerRegisterFontURLs(fontURLs as CFArray, .process, true) { _, _ in
            true
        }
    }

    private nonisolated static func fontURL(for assetName: String) -> URL? {
        if let url = Bundle.main.url(forResource: assetName, withExtension: "otf") {
            return url
        }
        return Bundle.main.url(forResource: assetName, withExtension: "otf", subdirectory: "Fonts")
    }
}
