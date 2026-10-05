import SwiftUI

/// The Claude Code part of the Ulanzi tab: whether the relay's door is
/// open, whether the hook is in Claude Code, and the button that puts it
/// there or takes it out. Its words are the model's.
struct UlanziClaudeCodeSection: View {
    @ObservedObject var model: UlanziStatusModel

    var body: some View {
        Section {
            Label(model.hubLine, systemImage: hubSymbol)
                .foregroundStyle(hubColor)
            Label(model.hookLine, systemImage: hookSymbol)
                .foregroundStyle(hookColor)

            if let failure = model.hookFailure {
                Label(loc("Échec : \(failure)", en: "Failed: \(failure)"), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if model.hook == .installed {
                Button(loc("Retirer le hook", en: "Remove the hook")) { model.removeHook?() }
            } else {
                // Only a hook known to be absent can go in: settings that
                // can't be read are never written over.
                Button(loc("Installer le hook", en: "Install the hook")) { model.installHook?() }
                    .disabled(model.hook != .absent)
            }
        } header: {
            Text(verbatim: "Claude Code")
        } footer: {
            Text(loc("Le hook est un petit script Python qui transmet chaque événement de session à Claudio. Il est écrit dans ~/.claude/settings.json après une copie de sauvegarde.",
                     en: "The hook is a small Python script that hands every session event to Claudio. It is written into ~/.claude/settings.json after a backup copy."))
                .settingsNote()
        }
    }

    private var hubSymbol: String {
        switch model.hub {
        case .off: "power"
        case .listening: "antenna.radiowaves.left.and.right"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var hubColor: Color {
        switch model.hub {
        case .off: .secondary
        case .listening: .green
        case .failed: .red
        }
    }

    private var hookSymbol: String {
        switch model.hook {
        case .installed: "checkmark.circle"
        case .absent: "circle.dashed"
        case .unreadable, .noRelay: "exclamationmark.triangle"
        }
    }

    private var hookColor: Color {
        switch model.hook {
        case .installed: .green
        case .absent: .secondary
        case .unreadable: .red
        case .noRelay: .orange
        }
    }
}
