import Foundation

enum FormURLEncoder {
    static func encode(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values.sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        // URL queries allow a literal plus, but form decoders treat it as space.
        let encoded = (components.percentEncodedQuery ?? "")
            .replacingOccurrences(of: "+", with: "%2B")
        return Data(encoded.utf8)
    }
}
