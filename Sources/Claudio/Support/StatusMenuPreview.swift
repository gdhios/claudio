import AppKit
import SwiftUI

/// `barre-de-menus`: the menu under Claudio as it opens, drawn from the very
/// rows the menu is made of. An open `NSMenu` belongs to the window server
/// and can't be rendered off screen, so this view lays the rows out the way
/// the menu does: icon, title, shortcut on the right, a chevron for a
/// submenu. Frozen for the shot: an update waiting, both histories with
/// something in them, the three status lines filled in by hand and the
/// default shortcuts. Nothing here reads this Mac.
@MainActor
enum StatusMenuPreview {
    static var rows: [StatusMenuRow] {
        let clocks = [UlanziClock(name: "Bureau", address: URL(string: "http://192.168.1.22")!),
                      UlanziClock(name: "Salon", address: URL(string: "http://192.168.1.23")!)]
            .map { UlanziStatusModel.ClockRow(clock: $0, faceStatus: .ready, alertsStatus: .ready) }
        let lines = StatusMenuLines(
            dictation: StatusMenuLines.dictation(enabled: true, key: LoneModifierKey.rightOption.title),
            ulanzi: StatusMenuLines.ulanzi(clocks),
            streamDeck: StatusMenuLines.streamDeck(status: .connected(clients: 1), pluginInstalled: true, choice: nil))
        return StatusMenuRows.build(update: .init(version: "1.14"), hasRecents: true, hasRecentDictations: true,
                                    lines: lines)
    }

    static func show() {
        let hosting = NSHostingView(rootView: StatusMenuPreviewView(rows: rows))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = loc("Barre de menus", en: "Menu bar")
        window.contentView = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

/// A strip of menu bar with Claudio in it, and the menu hanging under him.
private struct StatusMenuPreviewView: View {
    let rows: [StatusMenuRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: ClaudioMascot.menuBarImage())
                .renderingMode(.template)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    switch row {
                    case .separator:
                        Divider().padding(.horizontal, 10).padding(.vertical, 5)
                    case .header(let title):
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                            .padding(.bottom, 2)
                    case .item(let item):
                        StatusMenuPreviewRow(item: item)
                    }
                }
            }
            .padding(.vertical, 5)
        }
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct StatusMenuPreviewRow: View {
    let item: StatusMenuItem

    var body: some View {
        HStack(spacing: 7) {
            // The column stays for a row without an icon: titles line up.
            Group {
                if let symbol = item.symbol { Image(systemName: symbol) } else { Color.clear }
            }
            .frame(width: 18)
            Text(item.title).lineLimit(1)
            Spacer(minLength: 20)
            if item.opensSubmenu {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else if let trailing {
                Text(trailing).foregroundStyle(.secondary)
            }
        }
        .font(Font(NSFont.menuFont(ofSize: 0)))
        .foregroundStyle(item.isEnabled ? .primary : .tertiary)
        .padding(.horizontal, 12)
        .frame(height: 22)
    }

    /// The default shortcut rather than this Mac's: the shot is the same on
    /// every machine.
    private var trailing: String? {
        if let shortcut = item.shortcut { return shortcut.initialShortcut?.description }
        return item.keyEquivalent.isEmpty ? nil : "⌘" + item.keyEquivalent.uppercased()
    }
}
