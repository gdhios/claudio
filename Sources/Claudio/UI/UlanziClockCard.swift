import SwiftUI

/// One clock in the Ulanzi tab, as a card: its name, its address, its two
/// roles ticked or not with where each stands, and its two buttons. What
/// it edits is the card as typed; what it shows of the clock is the row
/// the model keeps, nil while the card is no clock yet.
struct UlanziClockCard: View {
    @Binding var draft: UlanziStatusModel.ClockDraft
    let row: UlanziStatusModel.ClockRow?
    /// The address typed last could not be read.
    let unreadable: Bool
    /// The first card carries the title of them all.
    let isFirst: Bool
    let submit: () -> Void
    let test: () -> Void
    let remove: () -> Void

    var body: some View {
        Section {
            TextField(loc("Nom", en: "Name"), text: $draft.name, prompt: Text(verbatim: UlanziClock.firstName))
                .onSubmit(submit)
            TextField(loc("Adresse", en: "Address"), text: $draft.address,
                      prompt: Text(verbatim: "192.168.1.22"))
                .onSubmit(submit)

            if unreadable {
                Label(loc("Adresse illisible : attendu « 192.168.1.22 ».",
                          en: "Unreadable address: expected “192.168.1.22”."),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            role(loc("Visage", en: "Face"), isOn: $draft.face,
                 status: row.map { UlanziStatusLook(face: $0.faceStatus) })
            role(loc("Fanions Claude Code", en: "Claude Code flags"), isOn: $draft.alerts,
                 status: row?.alertsStatus.map(UlanziStatusLook.init(alerts:)))

            HStack {
                Button(loc("Tester", en: "Test"), action: test)
                    .disabled(!draft.face || draft.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Button(loc("Retirer", en: "Remove"), role: .destructive, action: remove)
            }
        } header: {
            if isFirst { Text(loc("Horloges", en: "Clocks")) }
        }
        // A role ticked or unticked is applied at once, like a switch.
        .onChange(of: draft.face) { submit() }
        .onChange(of: draft.alerts) { submit() }
    }

    /// A role's box, and where it stands once ticked.
    private func role(_ title: String, isOn: Binding<Bool>, status: UlanziStatusLook?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Toggle(title, isOn: isOn)
                .toggleStyle(.checkbox)
            Spacer()
            if isOn.wrappedValue, let status {
                Label(status.line, systemImage: status.symbol)
                    .foregroundStyle(status.color)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

/// How a status looks in the tab: its words, which are the model's, a
/// symbol and a colour.
struct UlanziStatusLook {
    let line: String
    let symbol: String
    let color: Color

    init(face status: UlanziBridge.Status) {
        line = UlanziStatusModel.faceLine(status)
        switch status {
        case .off: (symbol, color) = ("power", .secondary)
        case .installing: (symbol, color) = ("clock", .orange)
        case .ready: (symbol, color) = ("checkmark.circle", .green)
        case .failed: (symbol, color) = ("exclamationmark.triangle", .red)
        }
    }

    init(alerts status: ClaudeCodeHub.ClockStatus) {
        line = UlanziStatusModel.alertsLine(status)
        switch status {
        case .pending: (symbol, color) = ("clock", .orange)
        case .ready: (symbol, color) = ("checkmark.circle", .green)
        case .unreachable, .rejected: (symbol, color) = ("exclamationmark.triangle", .red)
        }
    }
}
