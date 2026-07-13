import Foundation

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var strippingMarkdownHeading: String {
        drop(while: { $0 == "#" || $0.isWhitespace }).description
    }

    var strippingListMarker: String {
        let value = trimmed

        for marker in ["- ", "* ", "• "] where value.hasPrefix(marker) {
            return String(value.dropFirst(marker.count)).trimmed
        }

        if let separator = value.firstIndex(where: { $0 == "." || $0 == ")" }) {
            let prefix = value[..<separator]
            if !prefix.isEmpty, prefix.allSatisfy(\.isNumber) {
                return String(value[value.index(after: separator)...]).trimmed
            }
        }

        return value
    }

    var keyValuePair: (key: String, value: String)? {
        guard let separator = firstIndex(of: ":") else { return nil }

        let key = String(self[..<separator]).trimmed
        let value = String(self[index(after: separator)...]).trimmed
        guard !key.isEmpty, !value.isEmpty else { return nil }

        return (key, value)
    }
}
