extension String {
    /// The text on a single line: every run of whitespace, line breaks
    /// included, becomes one space, and none is left at either end.
    func collapsingWhitespace() -> String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The text as a menu row: on a single line, cut with "…" past `length`
    /// characters, the "…" included, so the row never stretches the menu.
    /// Counted in Swift characters (an accent with its letter, a whole
    /// emoji), so a cut never splits one.
    func menuRowTitle(length: Int) -> String {
        let flat = collapsingWhitespace()
        guard flat.count > length else { return flat }
        return flat.prefix(length - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}
