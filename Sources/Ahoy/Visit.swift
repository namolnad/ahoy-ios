public struct Visit: Sendable {
    public let visitorToken: String
    public let visitToken: String
    public internal(set) var userId: String? = nil
    public internal(set) var additionalParams: [String: any Encodable & Sendable]? = nil
}

extension Visit: Decodable {
    enum CodingKeys: String, CodingKey {
        case visitorToken
        case visitToken
    }
}
