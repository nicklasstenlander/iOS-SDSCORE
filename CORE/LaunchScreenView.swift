import SwiftUI

struct LaunchScreenView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.sdsDarkGreen, .sdsMidGreen],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Text("CORE")
                .font(SDSType.agrandir(56, weight: .bold))
                .foregroundColor(.white)
                .opacity(pulse ? 0.55 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
        }
        .onAppear {
            pulse = true
        }
    }
}
