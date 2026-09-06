import AppKit
import SwiftUI

/// The action palette: the whole catalog in view, filterable as you
/// type, and a last row that reuses the input as a custom instruction
/// when nothing fits. The same frame as the result panel: it's the
/// same object, transformed once the action is chosen.
struct PaletteView: View {
    @ObservedObject var session: CorrectionSession
    /// Body text size, set in Settings (General → Panel).
    var textSize: PanelTextSize = .normal
    /// Launches the row at the given index.
    let onLaunch: (Int) -> Void

    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            question
            rows
            ClaudioTheme.panelSeparator.frame(height: 1).padding(.top, 10)
            field
            hints
        }
        .onAppear {
            // The pointer is wherever the shortcut was triggered: hovering over it
            // only counts as a choice once it has moved.
            session.armHover(at: NSEvent.mouseLocation)
            // Same precaution as for the instruction field: focus set
            // in the appearance cycle is lost, a turn later it holds.
            Task { @MainActor in queryFocused = true }
        }
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(loc("Que faire de la sélection ?", en: "What should Claudio do with it?"))
                .font(.system(size: textSize.points(12), weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
            Text(session.originalText)
                .font(.system(size: textSize.points(10)))
                .foregroundStyle(.white.opacity(0.32))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 9)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(session.paletteRows.enumerated()), id: \.element.id) { index, row in
                PaletteRowView(row: row,
                               number: index + 1,
                               isSelected: index == session.paletteSelection,
                               textSize: textSize)
                    .contentShape(Rectangle())
                    .onHover {
                        guard $0, session.acceptsHover(at: NSEvent.mouseLocation) else { return }
                        session.paletteSelection = index
                    }
                    .onTapGesture { onLaunch(index) }
            }
        }
        .padding(.horizontal, 10)
    }

    /// The field does two jobs at once: it filters the catalog, and whatever
    /// stays written in it becomes the instruction if it's the last row that gets launched.
    private var field: some View {
        HStack(spacing: 10) {
            TextField("", text: $session.paletteQuery,
                      prompt: Text(loc("Filtrer, ou écrire une consigne…", en: "Filter, or write an instruction…"))
                        .foregroundStyle(.white.opacity(0.3)))
                .textFieldStyle(.plain)
                .font(.system(size: textSize.bodyPoints))
                .foregroundStyle(.white.opacity(0.95))
                .focused($queryFocused)
                .onSubmit { onLaunch(session.paletteSelection) }
            Text("⏎")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.34))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private var hints: some View {
        HStack(spacing: 12) {
            Text(loc("↑↓ naviguer", en: "↑↓ move"))
            // The bare digit launches as long as nothing is written; after that, it
            // gets typed, and it's ⌘ that launches. The hint follows suit rather
            // than half-promising.
            Text(session.paletteQuery.isEmpty ? loc("1–9 lancer", en: "1–9 run")
                                              : loc("⌘1–9 lancer", en: "⌘1–9 run"))
            Text(loc("échap fermer", en: "esc close"))
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.28))
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

/// A row: its rank, its icon, what it does in two lines, its
/// shortcut. Selection is announced with a plain inversion rather than
/// a color: the only colors in the list are the actions' icons.
private struct PaletteRowView: View {
    let row: PaletteRow
    let number: Int
    let isSelected: Bool
    /// The action's label follows the size setting; the rank, icon and
    /// shortcut stay fixed: they're landmarks, not reading material.
    var textSize: PanelTextSize = .normal

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(isSelected ? ClaudioTheme.panelBackground : .white.opacity(0.42))
                .frame(width: 22, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.88) : Color.white.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(.white.opacity(isSelected ? 0 : 0.08))
                )

            Image(systemName: row.origin.symbolName)
                .font(.system(size: 12.5))
                .foregroundStyle(row.origin.tint.opacity(isSelected ? 1 : 0.75))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.system(size: textSize.points(12.2), weight: .medium))
                    .foregroundStyle(.white.opacity(isSelected ? 1 : 0.78))
                    .lineLimit(1)
                Text(row.detail)
                    .font(.system(size: textSize.points(10.5)))
                    .foregroundStyle(.white.opacity(isSelected ? 0.5 : 0.38))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if !row.trailing.isEmpty {
                Text(row.trailing)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.06), in: Capsule())
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.10) : Color.white.opacity(0.028))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? .white.opacity(0.34) : .white.opacity(0.045))
        )
    }
}

/// Today's spending in the palette header: the moment you pick an
/// action is the right moment to see what the day has cost. Absent if the
/// counter is disabled in Settings.
struct CostGauge: View {
    @ObservedObject private var ledger = CostLedger.shared

    var body: some View {
        if AppSettings.costCounterEnabled {
            HStack(spacing: 5) {
                Text(loc("auj.", en: "today"))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                Text(ledger.day.formattedTotal)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.055), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.06), lineWidth: 1))
            .onAppear { ledger.refresh() }
        }
    }
}
