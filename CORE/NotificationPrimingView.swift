import SwiftUI

struct NotificationPrimingView: View {
    @EnvironmentObject private var push: PushNotificationService
    @State private var isActivating = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "bell.badge")
                    .font(.system(size: 72, weight: .ultraLight))
                    .foregroundColor(.sdsMidGreen)
                    .padding(.bottom, 40)

                Text("Håll dig nära\ndansglädjen")
                    .font(.custom("Agrandir-GrandLight", size: 30))
                    .foregroundColor(.sdsText)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)

                Text("Få veta direkt när något händer på skolan — nya kurser, öppet hus, nyheter och annat kul värt att inte missa.")
                    .font(.custom("Agrandir-Regular", size: 17))
                    .foregroundColor(.sdsMutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                Spacer()

                VStack(spacing: 16) {
                    Button {
                        isActivating = true
                        Task {
                            await push.requestPermissionAndRegister()
                            push.hasSeenNotificationPrompt = true
                        }
                    } label: {
                        ZStack {
                            if isActivating {
                                ProgressView()
                                    .tint(.sdsDarkGreen)
                            } else {
                                Text("Aktivera notiser")
                                    .font(.custom("Agrandir-TextBold", size: 20))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(Color.sdsMidGreen)
                        .foregroundColor(.sdsDarkGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isActivating)

                    Button {
                        push.hasSeenNotificationPrompt = true
                    } label: {
                        Text("Inte nu")
                            .font(.custom("Agrandir-Regular", size: 17))
                            .foregroundColor(.sdsMutedText)
                            .frame(height: 44)
                    }
                    .disabled(isActivating)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 52)
            }
        }
    }
}
