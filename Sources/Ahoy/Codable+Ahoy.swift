import Foundation

extension Encodable {
    func encode(to container: inout SingleValueEncodingContainer) throws {
        try container.encode(self)
    }
}

struct AnyEncodable: Encodable, Sendable {
    let wrapped: any Encodable & Sendable

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try wrapped.encode(to: &container)
    }
}

extension KeyedEncodingContainer {
    mutating func encode<Key: Encodable>(_ dictionary: [Key: any Encodable & Sendable], forKey key: K) throws {
        try encode(dictionary.mapValues(AnyEncodable.init(wrapped:)), forKey: key)
    }
}
