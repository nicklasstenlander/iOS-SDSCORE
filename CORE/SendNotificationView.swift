import SwiftUI

struct SendNotificationView: View {
    @EnvironmentObject private var auth: SupabaseAuthService
    @EnvironmentObject private var cogWork: CogWorkService

    @State private var notifTitle = ""
    @State private var message = ""
    @State private var audience: Audience = .all
    @State private var selectedEventId: Int?
    @State private var showConfirmation = false
    @State private var isSending = false
    @State private var sendResult: SendResult?
    @State private var errorText: String?

    private let maxTitleLength = 50
    private let maxMessageLength = 150
    private let workerBaseURL = "https://sds-cogwork-proxy.nicklas-stenlander.workers.dev"

    enum Audience: CaseIterable {
        case all
        case courseFollowers

        var label: String {
            switch self {
            case .all: return "Alla med appen"
            case .courseFollowers: return "Följare av kurs"
            }
        }
    }

    struct SendResult {
        let sent: Int
        let failed: Int
    }

    var body: some View {
        List {
            contentSection
            audienceSection

            if let result = sendResult { resultSection(result) }
            if let error = errorText { errorSection(error) }

            sendSection
        }
        .font(SDSType.agrandir(15))
        .navigationTitle("Skicka notis")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.sdsPageBackground)
        .confirmationDialog(confirmationTitle, isPresented: $showConfirmation, titleVisibility: .visible) {
            Button("Skicka") {
                Task { await send() }
            }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Detta går inte att ångra.")
        }
        .task {
            if cogWork.events.isEmpty {
                await cogWork.loadEvents()
            }
        }
    }

    // MARK: - Sektioner

    private var contentSection: some View {
        Section("Innehåll") {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Titel", text: $notifTitle)
                    .font(SDSType.agrandir(15))
                    .onChange(of: notifTitle) { _, new in
                        if new.count > maxTitleLength { notifTitle = String(new.prefix(maxTitleLength)) }
                    }
                HStack {
                    Spacer()
                    Text("\(notifTitle.count)/\(maxTitleLength)")
                        .font(SDSType.agrandir(11))
                        .foregroundColor(notifTitle.count >= maxTitleLength ? .sdsPink : .sdsMutedText)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("Meddelande", text: $message, axis: .vertical)
                    .font(SDSType.agrandir(15))
                    .lineLimit(3...6)
                    .onChange(of: message) { _, new in
                        if new.count > maxMessageLength { message = String(new.prefix(maxMessageLength)) }
                    }
                HStack {
                    Spacer()
                    Text("\(message.count)/\(maxMessageLength)")
                        .font(SDSType.agrandir(11))
                        .foregroundColor(message.count >= maxMessageLength ? .sdsPink : .sdsMutedText)
                }
            }
        }
    }

    private var audienceSection: some View {
        Section("Mottagare") {
            Picker("Mottagare", selection: $audience) {
                ForEach(Audience.allCases, id: \.label) { a in
                    Text(a.label).tag(a)
                }
            }
            .pickerStyle(.menu)
            .tint(.sdsDarkModeGreen)

            if audience == .courseFollowers {
                Picker("Kurs", selection: $selectedEventId) {
                    Text("Välj kurs…").tag(Optional<Int>.none)
                    ForEach(cogWork.events) { event in
                        Text(event.name ?? "–").tag(Optional(event.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(.sdsDarkModeGreen)
            }
        }
    }

    private func resultSection(_ result: SendResult) -> some View {
        Section {
            Label(
                "Skickad till \(result.sent) enhet(er). Misslyckades: \(result.failed).",
                systemImage: "checkmark.circle.fill"
            )
            .font(SDSType.agrandir(14))
            .foregroundColor(.sdsDarkModeGreen)
        }
    }

    private func errorSection(_ error: String) -> some View {
        Section {
            Text(error)
                .font(SDSType.agrandir(13))
                .foregroundColor(.sdsPink)
        }
        .listRowBackground(Color.sdsPinkAdaptiveSurface)
    }

    private var sendSection: some View {
        let canSend = !notifTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (audience == .all || selectedEventId != nil)

        return Section {
            Button {
                showConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    if isSending {
                        ProgressView().tint(.sdsDarkGreen)
                    } else {
                        Text("Skicka notis")
                            .font(SDSType.agrandir(17, weight: .bold))
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
            }
            .disabled(!canSend || isSending)
            .listRowBackground(canSend && !isSending ? Color.sdsMidGreen : Color.sdsSubtleSurface)
            .foregroundColor(.sdsDarkGreen)
        }
    }

    private var confirmationTitle: String {
        switch audience {
        case .all:
            return "Skicka till alla med appen?"
        case .courseFollowers:
            let name = cogWork.events.first(where: { $0.id == selectedEventId })?.name ?? "kursen"
            return "Skicka till följare av \(name)?"
        }
    }

    // MARK: - Skicka

    private func send() async {
        isSending = true
        errorText = nil
        sendResult = nil
        defer { isSending = false }

        guard let token = try? await auth.validAccessToken() else {
            errorText = "Autentiseringsfel. Försök logga in igen."
            return
        }

        guard let url = URL(string: "\(workerBaseURL)/push/send-custom") else {
            errorText = "Ogiltig serveradress."
            return
        }

        var target: [String: Any] = [
            "type": audience == .all ? "all" : "course"
        ]
        if audience == .courseFollowers, let eventId = selectedEventId {
            target["eventId"] = eventId
        }

        let payload: [String: Any] = [
            "title": notifTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            "message": message.trimmingCharacters(in: .whitespacesAndNewlines),
            "target": target
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            errorText = "Kunde inte skapa meddelande."
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorText = "Serverfel. Försök igen."
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                errorText = "Serverfel (\(http.statusCode)). Kontrollera Worker-loggar."
                return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                sendResult = SendResult(
                    sent: json["sent"] as? Int ?? 0,
                    failed: json["failed"] as? Int ?? 0
                )
            } else {
                sendResult = SendResult(sent: 0, failed: 0)
            }
        } catch let urlError as URLError where urlError.code == .networkConnectionLost {
            // Workern stängde förbindelsen utan HTTP-svar — troligen ett ohanterat undantag.
            // Försök en gång till med ny förbindelse.
            do {
                let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    errorText = "Worker stängde förbindelsen. Kontrollera Worker-loggar och försök igen."
                    return
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    sendResult = SendResult(
                        sent: json["sent"] as? Int ?? 0,
                        failed: json["failed"] as? Int ?? 0
                    )
                } else {
                    sendResult = SendResult(sent: 0, failed: 0)
                }
            } catch {
                errorText = "Worker svarar inte. Kontrollera att /push/send-custom är driftsatt och försök igen."
            }
        } catch {
            errorText = "Nätverksfel: \(error.localizedDescription)"
        }
    }
}
