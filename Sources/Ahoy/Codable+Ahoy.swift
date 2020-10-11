import Foundation

extension Encodable {
    func encode(to container: inout SingleValueEncodingContainer) throws {
        try container.encode(self)
    }
}

struct AnyEncodable: Encodable {
    let wrapped: Encodable

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try wrapped.encode(to: &container)
    }
}

extension KeyedEncodingContainer {
    mutating func encode<Key: Encodable>(_ dictionary: [Key: Encodable], forKey key: K) throws {
        try encode(dictionary.mapValues(AnyEncodable.init(wrapped:)), forKey: key)
    }
}
