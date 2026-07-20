import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: SupabaseAuthService
    @EnvironmentObject var cogWork: CogWorkService
    @State private var email = ""
    @State private var password = ""
    @State private var temporaryPassword = ""
    @State private var showsPassword = false
    @State private var showsTemporaryPassword = false
    @State private var showsLoginHelp = false
    @State private var showsPasswordResetEntry = false
    @State private var showsPasswordResetConfirmation = false
    @State private var passwordResetEmail = ""

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                Color.white
                    .ignoresSafeArea()

                Image("SDSLoginBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height * 0.38, alignment: .bottom)
                    .clipped()
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.18),
                                .init(color: .black, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(edges: .bottom)

                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 46)

                        brandHeader(for: proxy.size.width)

                        formContent(for: proxy.size.width)
                            .frame(maxWidth: proxy.size.width >= 390 ? 360 : 280)
                            .padding(.horizontal, 16)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        #if DEBUG
        .onAppear {
            email = DebugCredentialStore.email
            password = DebugCredentialStore.password
            temporaryPassword = DebugCredentialStore.password
        }
        #endif
        .alert("Återställ lösenord", isPresented: $showsPasswordResetEntry) {
            TextField("E-mailadress", text: $passwordResetEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            Button("Skicka") {
                Task { await auth.sendPasswordReset(email: passwordResetEmail) }
                showsPasswordResetConfirmation = true
            }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Ange din e-postadress för att få en återställningslänk.")
        }
        .alert("E-post skickat", isPresented: $showsPasswordResetConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Om adressen finns registrerad skickas en återställningslänk inom kort.")
        }
    }

    private func brandHeader(for width: CGFloat) -> some View {
        VStack(spacing: 0) {
            Image("SDSDancerLoginLogo")
                .resizable()
                .scaledToFit()
                .frame(width: dancerWidth(for: width), height: dancerLogoHeight(for: width))
                .padding(.bottom, 38)

            Text("CORE")
                .font(.custom("Agrandir-GrandLight", size: width >= 390 ? 48 : 36))
                .foregroundColor(.sdsText)
                .padding(.bottom, 14)

            Text("Kärnan i varje steg.")
                .font(.custom("Agrandir-Regular", size: width >= 390 ? 21 : 18))
                .foregroundColor(.sdsText)
                .multilineTextAlignment(.center)
                .padding(.bottom, 25)

                        .padding(.bottom, 52)
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 16)
    }

    private func formContent(for width: CGFloat) -> some View {
        VStack(spacing: 10) {
            if let error = auth.errorMessage {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.sdsPink)
                        .frame(width: 4, height: 4)

                    Text(error)
                        .font(.custom("Agrandir-Regular", size: 12))
                        .foregroundColor(.sdsPink)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        auth.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.sdsPink)
                    }
                }
                .padding(.bottom, 2)
            }

            SDSLoginField(
                label: "E-mailadress",
                placeholder: "namn@sollentunadans.se",
                text: $email,
                keyboard: .emailAddress
            )

            VStack(alignment: .leading, spacing: 8) {
                SDSLoginField(
                    label: "Lösenord",
                    placeholder: "••••••••••",
                    text: $password,
                    isSecure: !showsPassword,
                    trailingIcon: showsPassword ? "eye.slash" : "eye"
                ) {
                    showsPassword.toggle()
                }

                Button("Glömt lösenord?") {
                    passwordResetEmail = email
                    showsPasswordResetEntry = true
                }
                    .font(.custom("Agrandir-Regular", size: 12))
                    .foregroundColor(.sdsMutedText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Button {
                Task { await signIn() }
            } label: {
                ZStack {
                    if auth.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Logga in")
                            .font(.custom("Agrandir-TextBold", size: 22))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 68)
                .background(Color.sdsTeal)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(auth.isLoading)
            .padding(.top, 18)

            Text("© \(String(Calendar.current.component(.year, from: Date()))) Moon Movements AB")
                .font(.custom("Agrandir-Regular", size: width >= 390 ? 16 : 14))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .padding(.top, 26)

            Rectangle()
                .fill(Color.sdsLightGreen)
                .frame(height: 1)
                .padding(.top, 20)

            DisclosureGroup(isExpanded: $showsLoginHelp) {
                VStack(alignment: .leading, spacing: 10) {
                    SDSLoginField(
                        label: "Tillfälligt lösenord",
                        placeholder: "••••••••••",
                        text: $temporaryPassword,
                        isSecure: !showsTemporaryPassword,
                        trailingIcon: showsTemporaryPassword ? "eye.slash" : "eye"
                    ) {
                        showsTemporaryPassword.toggle()
                    }

                    Button {
                        Task { await signInWithTemporaryPassword() }
                    } label: {
                        Text("Använd tillfälligt lösenord")
                            .font(.custom("Agrandir-TextBold", size: 13))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.sdsLightGreen)
                            .foregroundColor(.sdsDarkGreen)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(auth.isLoading || temporaryPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Text("Det tillfälliga lösenordet används också som CogWork API-lösenord.")
                        .font(.custom("Agrandir-Regular", size: 12))
                        .foregroundColor(.sdsMutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 10)
            } label: {
                Text("Problem att logga in? Använd tillfälligt lösenord")
                    .font(.custom("Agrandir-Regular", size: 12))
                    .foregroundColor(.sdsMutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .tint(.sdsMutedText)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
    }

    private func signIn() async {
        await auth.signIn(email: email, password: password)

        #if DEBUG
        if auth.isAuthenticated && auth.errorMessage == nil {
            DebugCredentialStore.email = email
            DebugCredentialStore.password = password
        }
        #endif
    }

    private func signInWithTemporaryPassword() async {
        let trimmedPassword = temporaryPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPassword.isEmpty else { return }

        password = trimmedPassword
        await auth.signIn(email: email, password: trimmedPassword)

        if auth.isAuthenticated && auth.errorMessage == nil {
            cogWork.cogWorkPassword = trimmedPassword

            #if DEBUG
            DebugCredentialStore.email = email
            DebugCredentialStore.password = trimmedPassword
            #endif
        }
    }

    private func logoSize(for width: CGFloat) -> CGFloat {
        width >= 390 ? 115 : 97
    }

    private func dancerWidth(for width: CGFloat) -> CGFloat {
        min(max(width * 0.30, 110), 180)
    }

    private func dancerLogoHeight(for width: CGFloat) -> CGFloat {
        width >= 390 ? 158 : 132
    }
}

private struct SDSLoginField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var isSecure = false
    var trailingIcon: String?
    var trailingAction: (() -> Void)?

    init(
        label: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        isSecure: Bool = false,
        trailingIcon: String? = nil,
        trailingAction: (() -> Void)? = nil
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.keyboard = keyboard
        self.isSecure = isSecure
        self.trailingIcon = trailingIcon
        self.trailingAction = trailingAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(SDSType.agrandir(14))
                .foregroundColor(.sdsText)

            HStack(spacing: 10) {
                Group {
                    if isSecure {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .font(SDSType.agrandir(14))
                .foregroundColor(.sdsText)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                if let trailingIcon {
                    Button {
                        trailingAction?()
                    } label: {
                        Image(systemName: trailingIcon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.sdsMutedText)
                            .frame(width: 24, height: 24)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.sdsText, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(SupabaseAuthService())
        .environmentObject(CogWorkService())
}
