import SwiftUI

/// The Ulanzi tab: what the clock is for, where it is, whether it answers,
/// and a button to see Claudio smile on it.
///
/// Everything shown comes from `UlanziStatusModel`, which the app fills in:
/// the pane reads no preference and calls no device, so a preview renders
/// the same screen on every machine, and its Test button does nothing.
struct UlanziPane: View {
    @ObservedObject private var model = UlanziStatusModel.shared
    /// The field as typed; the address kept is the model's.
    @State private var field = UlanziStatusModel.shared.address
    /// The last address submitted could not be read, and the kept one is
    /// back in the field: said until the next one is.
    @State private var unreadable = false

    var body: some View {
        Form {
            what
            device
        }
        .formStyle(.grouped)
    }

    // MARK: - What the clock is for

    private var what: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(systemName: SettingsSection.ulanzi.symbolName,
                          color: SettingsSection.ulanzi.color)
                Text(loc("Claudio montre sa tête sur un Ulanzi TC001 sous AWTRIX NG pendant qu'il travaille : ses yeux suivent ce qu'il fait.",
                         en: "Claudio shows his face on an Ulanzi TC001 running AWTRIX NG while he works: his eyes follow what he does."))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - The device

    private var device: some View {
        Section {
            TextField(loc("Adresse", en: "Address"), text: $field,
                      prompt: Text(verbatim: "192.168.1.22"))
                .onSubmit(submit)

            Label(model.statusLine, systemImage: statusSymbol)
                .foregroundStyle(statusColor)

            if unreadable {
                Label(loc("Adresse illisible : attendu « 192.168.1.22 ».",
                          en: "Unreadable address: expected “192.168.1.22”."),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button(loc("Tester", en: "Test")) {
                unreadable = !model.testTyped(field)
                field = model.address
            }
            .disabled(field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text(loc("Appareil", en: "Device"))
        } footer: {
            Text(loc("Rien n'est envoyé ailleurs que sur cette adresse, sur ton réseau local. Le visage s'installe tout seul sur l'appareil.",
                     en: "Nothing is sent anywhere but this address, on your local network. The face installs itself on the device."))
                .settingsNote()
        }
    }

    /// Empty switches the face off; an address nobody could call puts the
    /// kept one back in the field, and says so.
    private func submit() {
        unreadable = !model.submit(field)
        field = model.address
    }

    // MARK: - How the status looks (its words are the model's)

    private var statusSymbol: String {
        switch model.status {
        case .off: "power"
        case .installing: "clock"
        case .ready: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .off: .secondary
        case .installing: .orange
        case .ready: .green
        case .failed: .red
        }
    }
}
