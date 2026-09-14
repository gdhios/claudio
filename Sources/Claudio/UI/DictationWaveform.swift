import SwiftUI

/// The microphone's recent loudness as a row of bars, newest on the right.
/// Older bars fade toward the left so the eye reads which way it moves, and
/// a silent bar stays a dot: the panel shows it listens even before a word.
struct DictationWaveform: View {
    let levels: [Float]
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 3
    var maxHeight: CGFloat = 32
    var color: Color = ClaudioTheme.accent

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                Capsule()
                    .fill(color.opacity(opacity(at: index)))
                    .frame(width: barWidth, height: height(for: level))
            }
        }
        .frame(height: maxHeight)
        // Readings arrive about ten times a second: easing between them is
        // what turns steps into movement.
        .animation(.easeOut(duration: 0.12), value: levels)
        .accessibilityHidden(true)
    }

    private func height(for level: Float) -> CGFloat {
        barWidth + (maxHeight - barWidth) * CGFloat(level)
    }

    private func opacity(at index: Int) -> Double {
        guard levels.count > 1 else { return 1 }
        return 0.3 + 0.7 * Double(index) / Double(levels.count - 1)
    }
}
