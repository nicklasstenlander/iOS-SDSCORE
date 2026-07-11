import SwiftUI

struct LaunchScreenView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.white
            .ignoresSafeArea()

            Image("SDSDancerLoginLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
                .opacity(pulse ? 0.62 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
        }
        .onAppear {
            pulse = true
        }
    }
}

#Preview {
    LaunchScreenView()
}
