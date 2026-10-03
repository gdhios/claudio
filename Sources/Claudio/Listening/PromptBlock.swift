import Foundation

/// The shape every music block of a prompt shares: the opening tag, one
/// "label : value" line per field that has a value — none for the others,
/// a line saying a field is unknown would invite a guess — then whatever
/// else the block lists, and the closing tag.
enum PromptBlock {
    typealias Field = (label: String, value: String?)

    static func make(_ tag: String, attributes: String? = nil, fields: [Field], more: [String] = []) -> String {
        let opening = attributes.map { "<\(tag) \($0)>" } ?? "<\(tag)>"
        let lines = fields.compactMap { field in field.value.map { "\(field.label) : \($0)" } }
        return ([opening] + lines + more + ["</\(tag)>"]).joined(separator: "\n")
    }
}
