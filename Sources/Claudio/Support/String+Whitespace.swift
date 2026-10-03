extension String {
    /// The text on a single line: every run of whitespace, line breaks
    /// included, becomes one space, and none is left at either end.
    func collapsingWhitespace() -> String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
