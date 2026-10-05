import AppKit
import SwiftUI

/// The Tip tab: Claudio is free, and a coffee for whoever makes it is all
/// it asks. One button out to the page in the browser, and the address
/// under it for whoever would rather copy it. Nothing is paid in the app.
struct TipPane: View {
    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    IconBadge(systemName: SettingsSection.tip.symbolName,
                              color: SettingsSection.tip.color)
                    Text(loc("Claudio est gratuit et le restera. S'il te rend service, tu peux offrir un café à Guillaume, qui le fabrique le soir.",
                             en: "Claudio is free and will stay free. If it helps you, you can buy a coffee for Guillaume, who makes it in the evenings."))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        NSWorkspace.shared.open(Constants.tipURL)
                    } label: {
                        Label(loc("Offrir un café", en: "Buy a coffee"), systemImage: "cup.and.saucer")
                    }
                    .buttonStyle(.borderedProminent)
                    Text(Constants.tipURL.absoluteString)
                        .textSelection(.enabled)
                        .settingsNote()
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }
}
