import SwiftUI

extension View {
    /// The small grey line under a setting, in every pane: what it does,
    /// what it costs, where else it is set.
    func settingsNote() -> some View {
        font(.caption).foregroundStyle(.secondary)
    }
}

/// Under a prompt being edited, in Prompts and in Dictation: whether it is
/// still the app's own or has been rewritten, and the way back to the app's.
struct PromptStatusRow: View {
    let isCustomized: Bool
    let reset: () -> Void

    var body: some View {
        HStack {
            if isCustomized {
                Label(loc("Personnalisé", en: "Customised"), systemImage: "pencil")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Label(loc("Prompt par défaut", en: "Default prompt"), systemImage: "checkmark.circle")
                    .settingsNote()
            }
            Spacer()
            Button(loc("Réinitialiser", en: "Reset"), action: reset)
                .disabled(!isCustomized)
        }
    }
}
