extension String {
    /// Compared to the last byte whatever it finds: `==` stops at the first
    /// difference, and how long that takes tells a caller how much of the
    /// token they guessed right.
    func isEqualInConstantTime(to other: String) -> Bool {
        let mine = Array(utf8), theirs = Array(other.utf8)
        guard mine.count == theirs.count else { return false }
        return zip(mine, theirs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
