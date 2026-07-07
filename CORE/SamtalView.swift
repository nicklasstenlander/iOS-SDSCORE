import SwiftUI

struct SamtalView: View {
    @EnvironmentObject private var cogWork: CogWorkService
    @EnvironmentObject private var auth: SupabaseAuthService
    @StateObject private var telavox = TelavoxService()

    @State private var selectedDate = Date()
    @State private var smsDraft: SMSDraft?
    @State private var pendingDial: TelavoxCall?
    @State private var dialStatus: String?

    private var participantLookup: [String: ParticipantCallInfo] {
        SDSPhoneNumbers.participantLookup(for: cogWork.bookings)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    dateControls

                    if let errorMessage = telavox.errorMessage {
                        errorBanner(errorMessage)
                    }

                    if let dialStatus {
                        statusBanner(dialStatus)
                    }

                    if telavox.isLoading && telavox.calls.isEmpty {
                        loadingRows
                    } else {
                        callsContent
                    }
                }
                .padding(20)
            }
            .navigationTitle("Samtal")
            .background(Color.sdsPageBackground.ignoresSafeArea())
            .refreshable {
                await telavox.loadCalls(on: selectedDate)
            }
            .task {
                if telavox.calls.isEmpty {
                    await telavox.loadCalls(on: selectedDate)
                }
            }
            .onChange(of: selectedDate) { _, newValue in
                Task { await telavox.loadCalls(on: newValue) }
            }
            .sheet(item: $smsDraft) { draft in
                SMSComposerView(
                    draft: draft,
                    telavox: telavox,
                    telavoxAgent: auth.profile?.telavoxAgent
                )
            }
            .confirmationDialog(
                "Ring upp \(pendingDial?.number ?? "")",
                isPresented: Binding(
                    get: { pendingDial != nil },
                    set: { if !$0 { pendingDial = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Starta samtal") {
                    guard let call = pendingDial else { return }
                    Task { await dial(call.number) }
                }
                Button("Avbryt", role: .cancel) {
                    pendingDial = nil
                }
            } message: {
                Text("Telavox ringer först upp din telefon. Svara för att kopplas vidare till mottagaren.")
            }
        }
    }

    private var dateControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Samtal")
                    .font(SDSType.agrandir(28, weight: .bold))
                    .foregroundColor(.sdsDarkModeGreen)

                Spacer()

                Button {
                    Task { await telavox.loadCalls(on: selectedDate) }
                } label: {
                    Image(systemName: telavox.isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.system(size: 17, weight: .semibold))
                }
                .disabled(telavox.isLoading)
                .accessibilityLabel("Uppdatera")
            }

            HStack(spacing: 8) {
                SDSPill(title: "Idag", isSelected: Calendar.current.isDateInToday(selectedDate)) {
                    selectedDate = Date()
                }
                SDSPill(title: "Igår", isSelected: Calendar.current.isDateInYesterday(selectedDate)) {
                    selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                }
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden()
                    .tint(.sdsDarkModeGreen)
            }
        }
    }

    private var callsContent: some View {
        VStack(spacing: 14) {
            CallSectionView(
                title: "Missade",
                icon: "phone.down",
                color: .sdsPink,
                calls: calls(for: .missed),
                emptyText: "Inga missade samtal",
                participantLookup: participantLookup,
                onDial: { pendingDial = $0 },
                onSMS: openSMS
            )

            CallSectionView(
                title: "Inkommande",
                icon: "phone.arrow.down.left",
                color: .sdsDarkModeGreen,
                calls: calls(for: .incoming),
                emptyText: "Inga inkommande samtal",
                participantLookup: participantLookup,
                onDial: { pendingDial = $0 },
                onSMS: openSMS
            )

            CallSectionView(
                title: "Utgående",
                icon: "phone.arrow.up.right",
                color: .sdsSecondaryText,
                calls: calls(for: .outgoing),
                emptyText: "Inga utgående samtal",
                participantLookup: participantLookup,
                onDial: { pendingDial = $0 },
                onSMS: openSMS
            )
        }
    }

    private var loadingRows: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.sdsSubtleSurface)
                    .frame(height: 86)
                    .overlay(ProgressView().tint(.sdsDarkModeGreen))
            }
        }
    }

    private func calls(for direction: TelavoxCall.Direction) -> [TelavoxCall] {
        telavox.calls.filter { $0.direction == direction }
    }

    private func openSMS(_ call: TelavoxCall) {
        let lookup = participantLookup[SDSPhoneNumbers.lookupKey(call.number)]
        smsDraft = SMSDraft(
            number: call.number,
            recipientName: lookup?.name.nilIfEmpty ?? call.number
        )
    }

    private func dial(_ number: String) async {
        pendingDial = nil
        let ok = await telavox.dial(number: number)
        dialStatus = ok
            ? "Samtalet är startat. Din telefon ringer först."
            : "Kunde inte starta samtalet."
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(SDSType.agrandir(14, weight: .bold))
            .foregroundColor(.sdsPink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.sdsPinkAdaptiveSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statusBanner(_ message: String) -> some View {
        Text(message)
            .font(SDSType.agrandir(14, weight: .bold))
            .foregroundColor(.sdsDarkModeGreen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.sdsLightGreenSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct CallSectionView: View {
    let title: String
    let icon: String
    let color: Color
    let calls: [TelavoxCall]
    let emptyText: String
    let participantLookup: [String: ParticipantCallInfo]
    let onDial: (TelavoxCall) -> Void
    let onSMS: (TelavoxCall) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(SDSType.agrandir(15, weight: .bold))
                    .foregroundColor(.sdsDarkModeGreen)
                Text("(\(calls.count))")
                    .font(SDSType.agrandir(13))
                    .foregroundColor(.sdsSecondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if calls.isEmpty {
                Text(emptyText)
                    .font(SDSType.agrandir(14))
                    .foregroundColor(.sdsSecondaryText)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(calls) { call in
                        CallRowView(
                            call: call,
                            participant: participantLookup[SDSPhoneNumbers.lookupKey(call.number)],
                            onDial: { onDial(call) },
                            onSMS: { onSMS(call) }
                        )
                        if call.id != calls.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .background(Color.sdsSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.sdsBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct CallRowView: View {
    let call: TelavoxCall
    let participant: ParticipantCallInfo?
    let onDial: () -> Void
    let onSMS: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Self.timeFormatter.string(from: call.startDate ?? Date()))
                        .font(SDSType.agrandir(13, weight: .bold))
                        .foregroundColor(.sdsDarkModeGreen)
                        .monospacedDigit()

                    Text(participant?.name.nilIfEmpty ?? "Okänt nummer")
                        .font(SDSType.agrandir(14, weight: .bold))
                        .foregroundColor(.sdsPrimaryText)
                        .lineLimit(1)
                }

                Text(call.number)
                    .font(SDSType.agrandir(12))
                    .foregroundColor(.sdsSecondaryText)
                    .monospacedDigit()

                if let courses = participant?.courses, !courses.isEmpty {
                    Text(courses.joined(separator: ", "))
                        .font(SDSType.agrandir(12))
                        .foregroundColor(.sdsSecondaryText)
                        .lineLimit(1)
                }

                Text(durationText)
                    .font(SDSType.agrandir(12, weight: call.duration == 0 ? .bold : .regular))
                    .foregroundColor(call.duration == 0 ? .sdsPink : .sdsSecondaryText)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button(action: onDial) {
                    Image(systemName: "phone")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .tint(.sdsDarkModeGreen)
                .accessibilityLabel("Ring upp")

                Button(action: onSMS) {
                    Image(systemName: "message")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .tint(.sdsDarkModeGreen)
                .accessibilityLabel("Skicka SMS")
            }
        }
        .padding(16)
    }

    private var durationText: String {
        guard call.duration > 0 else { return "Missat" }
        let minutes = call.duration / 60
        let seconds = call.duration % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct SMSDraft: Identifiable {
    let id = UUID()
    let number: String
    let recipientName: String
}

private struct SMSComposerView: View {
    private let templates = [
        "Hej! Vi har en ledig plats på kursen. Hör av dig!",
        "Påminnelse: Betalning förfaller snart.",
        "Välkommen! Din plats är bekräftad."
    ]
    private let maxCharacters = 160

    let draft: SMSDraft
    @ObservedObject var telavox: TelavoxService
    let telavoxAgent: String?

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var sender = SDSPhoneNumbers.groupSender
    @State private var isSending = false
    @State private var resultMessage: String?

    private var senderOptions: [String] {
        let agent = telavoxAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let agent, !agent.isEmpty, agent != SDSPhoneNumbers.groupSender {
            return [SDSPhoneNumbers.groupSender, agent]
        }
        return [SDSPhoneNumbers.groupSender]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Mottagare", value: draft.recipientName)
                    LabeledContent("Nummer", value: draft.number)
                    Picker("Avsändare", selection: $sender) {
                        ForEach(senderOptions, id: \.self) { option in
                            Text(senderLabel(option)).tag(option)
                        }
                    }
                }

                Section("Mallar") {
                    ForEach(templates, id: \.self) { template in
                        Button(template) {
                            message = String(template.prefix(maxCharacters))
                        }
                        .foregroundColor(.sdsDarkModeGreen)
                    }
                }

                Section {
                    TextEditor(text: $message)
                        .font(SDSType.agrandir(15))
                        .frame(minHeight: 120)
                        .onChange(of: message) { _, newValue in
                            if newValue.count > maxCharacters {
                                message = String(newValue.prefix(maxCharacters))
                            }
                        }

                    HStack {
                        Spacer()
                        Text("\(message.count)/\(maxCharacters)")
                            .font(SDSType.agrandir(12))
                            .foregroundColor(message.count >= maxCharacters ? .sdsPink : .sdsSecondaryText)
                    }
                } header: {
                    Text("Meddelande")
                }

                if let resultMessage {
                    Section {
                        Text(resultMessage)
                            .font(SDSType.agrandir(14, weight: .bold))
                            .foregroundColor(resultMessage.contains("skickat") ? .sdsDarkModeGreen : .sdsPink)
                    }
                }
            }
            .font(SDSType.agrandir(15))
            .navigationTitle("Skicka SMS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Text("Skicka")
                        }
                    }
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
            }
            .onAppear {
                sender = senderOptions.first ?? SDSPhoneNumbers.groupSender
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func senderLabel(_ option: String) -> String {
        option == SDSPhoneNumbers.groupSender ? "Gruppnumret \(option)" : option
    }

    private func send() async {
        isSending = true
        defer { isSending = false }

        let ok = await telavox.sendSMS(
            number: draft.number,
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            sender: sender
        )
        if ok {
            resultMessage = "SMS skickat."
            dismiss()
        } else {
            resultMessage = "Kunde inte skicka SMS."
        }
    }
}
