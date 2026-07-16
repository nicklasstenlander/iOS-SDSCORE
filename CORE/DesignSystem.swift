import SwiftUI
import UIKit

// MARK: - SDS webbpalett

extension Color {
    static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        })
    }

    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: .init(charactersIn: "#")))
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    static let sdsLightGreen = Color(hex: "CFDED2")
    static let sdsDarkGreen = Color(hex: "1e4025")
    static let sdsMidGreen = Color(hex: "A0C4B9")
    static let sdsPink = Color(hex: "dd5c86")
    static let sdsTeal = Color(hex: "009399")
    static let sdsAqua = Color(hex: "45aba5")
    static let sdsPublicBackground = Color.adaptive(light: "ffffff", dark: "0c0c0c")
    static let sdsBackground = Color(hex: "f5f8f6")
    static let sdsCard = Color.white
    static let sdsText = Color(hex: "111111")
    static let sdsMutedText = Color.adaptive(light: "111111", dark: "f0f0f0").opacity(0.56)
    static let sdsSoftField = Color.sdsLightGreen.opacity(0.34)
    static let sdsPinkSurface = Color.sdsPink.opacity(0.12)
    static let sdsVioletSurface = Color(hex: "f0e7f4")
    static let sdsSkySurface = Color(hex: "e2f0f4")
    static let sdsAmberSurface = Color(hex: "f8edc0")
    static let sdsWarningText = Color(hex: "6b4f00")

    static let sdsPageBackground = Color.adaptive(light: "ffffff", dark: "111111")
    static let sdsSurface = Color.adaptive(light: "ffffff", dark: "1a1a1a")
    static let sdsElevatedSurface = Color.adaptive(light: "ffffff", dark: "202020")
    static let sdsPrimaryText = Color.adaptive(light: "111111", dark: "f0f0f0")
    static let sdsSecondaryText = Color.adaptive(light: "6f7a74", dark: "a0a0a0")
    static let sdsTertiaryText = Color.adaptive(light: "98a39d", dark: "858585")
    static let sdsBorder = Color.adaptive(light: "e6eee9", dark: "2a2a2a")
    static let sdsInputBackground = Color.adaptive(light: "ffffff", dark: "1f1f1f")
    static let sdsSubtleSurface = Color.adaptive(light: "f8fafc", dark: "171717")
    static let sdsPublicSubtleSurface = Color.adaptive(light: "f9f9f9", dark: "1c1c1c")
    static let sdsPublicBorder = Color.adaptive(light: "eeeeee", dark: "2c2c2c")
    static let sdsIconBackground = Color.adaptive(light: "ffffff", dark: "2a2a2a").opacity(0.72)
    static let sdsDarkModeGreen = Color.adaptive(light: "1e4025", dark: "A0C4B9")
    static let sdsLightGreenSurface = Color.adaptive(light: "CDDCD1", dark: "1f2f25")
    static let sdsPinkAdaptiveSurface = Color.adaptive(light: "fae8ef", dark: "2a1519")
    static let sdsAmberAdaptiveSurface = Color.adaptive(light: "f8edc0", dark: "2a2517")
    static let sdsVioletAdaptiveSurface = Color.adaptive(light: "f0e7f4", dark: "251f28")
    static let sdsSkyAdaptiveSurface = Color.adaptive(light: "e2f0f4", dark: "18242a")
}

// MARK: - Delade UI-komponenter

enum SDSType {
    enum Variant: String {
        case regular          = "Agrandir-Regular"
        case grandLight       = "Agrandir-GrandLight"
        case grandHeavy       = "Agrandir-GrandHeavy"
        case textBold         = "Agrandir-TextBold"
        case narrow           = "Agrandir-Narrow"
        case tight            = "Agrandir-Tight"
        case wideLight        = "Agrandir-WideLight"
        case wideBlackItalic  = "Agrandir-WideBlackItalic"
        case thinItalic       = "Agrandir-ThinItalic"
    }

    static func agrandir(_ size: CGFloat, variant: Variant) -> Font {
        guard UIFont(name: variant.rawValue, size: size) != nil else {
            assertionFailure("Missing Agrandir font: \(variant.rawValue)")
            return .system(size: size)
        }

        return .custom(variant.rawValue, size: size)
    }

    static func agrandir(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        agrandir(size, variant: variantForWeight(weight))
    }

    private static func variantForWeight(_ weight: Font.Weight) -> Variant {
        switch weight {
        case .black, .heavy:           return .grandHeavy
        case .bold, .semibold:         return .textBold
        case .light:                   return .wideLight
        case .thin, .ultraLight:       return .grandLight
        default:                       return Variant.regular
        }
    }
}

struct SDSHeroHeader: View {
    let title: String
    let tagline: String
    var height: CGFloat = 280
    var showsCopyright = true

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [.sdsDarkGreen, .sdsMidGreen],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: height)

            VStack(alignment: .leading, spacing: 7) {
                Text(title.uppercased())
                    .font(SDSType.agrandir(54, weight: .bold))
                    .foregroundColor(.white)

                Text(tagline)
                    .font(SDSType.agrandir(20, weight: .regular))
                    .italic()
                    .foregroundColor(.white.opacity(0.78))

                if showsCopyright {
                    Text("© \(Calendar.current.component(.year, from: Date())) Sollentuna Dans & Scenskola")
                        .font(SDSType.agrandir(12, weight: .regular))
                        .foregroundColor(.white.opacity(0.62))
                        .padding(.top, 22)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 26)
        }
        .clipShape(.rect(bottomLeadingRadius: 28, bottomTrailingRadius: 28))
    }
}

struct SDSPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(.sdsDarkGreen)
                } else {
                    Text(title)
                        .font(SDSType.agrandir(17, weight: .bold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Color.sdsMidGreen)
            .foregroundColor(.sdsDarkGreen)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(isLoading)
    }
}

struct SDSTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default
    @State private var showsSecureText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !label.isEmpty {
                Text(label.uppercased())
                    .font(SDSType.agrandir(12, weight: .bold))
                    .foregroundColor(.sdsDarkGreen)
            }

            fieldContent
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Color.sdsInputBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.sdsBorder, lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private var fieldContent: some View {
        if isSecure {
            HStack(spacing: 10) {
                Group {
                    if showsSecureText {
                        TextField(placeholder, text: $text)
                    } else {
                        SecureField(placeholder, text: $text)
                    }
                }
                .font(SDSType.agrandir(15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button {
                    showsSecureText.toggle()
                } label: {
                    Image(systemName: showsSecureText ? "eye.slash" : "eye")
                        .foregroundColor(.sdsDarkGreen)
                }
            }
        } else {
            TextField(placeholder, text: $text)
                .font(SDSType.agrandir(15))
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}

struct SDSPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(SDSType.agrandir(14, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(isSelected ? Color.sdsTeal : Color.sdsSurface)
                .foregroundColor(isSelected ? .white : .sdsDarkModeGreen)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.sdsBorder.opacity(isSelected ? 0 : 1), lineWidth: 1)
                )
        }
    }
}

struct SDSPeriodPicker: View {
    let periods: [Period]
    @Binding var selectedPeriod: Period
    var commitDelay: Duration = .milliseconds(180)

    @State private var displayedPeriod: Period?
    @State private var commitTask: Task<Void, Never>?

    private var visiblePeriod: Period {
        displayedPeriod ?? selectedPeriod
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(periods, id: \.self) { period in
                    SDSPill(title: period.displayName, isSelected: visiblePeriod == period) {
                        select(period)
                    }
                }
            }
        }
        .onAppear {
            displayedPeriod = selectedPeriod
        }
        .onChange(of: selectedPeriod) { _, newValue in
            if displayedPeriod != newValue {
                displayedPeriod = newValue
            }
        }
        .onDisappear {
            commitTask?.cancel()
        }
    }

    private func select(_ period: Period) {
        guard visiblePeriod != period else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            displayedPeriod = period
        }

        commitTask?.cancel()
        commitTask = Task {
            try? await Task.sleep(for: commitDelay)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                selectedPeriod = period
            }
        }
    }
}

struct SDSBadge: View {
    let text: String
    var color: Color = .sdsLightGreen
    var textColor: Color = .sdsDarkGreen

    var body: some View {
        Text(text)
            .font(SDSType.agrandir(12, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color)
            .foregroundColor(textColor)
            .clipShape(Capsule())
    }
}
