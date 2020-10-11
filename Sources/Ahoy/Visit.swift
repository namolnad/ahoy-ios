public struct Visit {
    public let visitorToken: String
    public let visitToken: String
    public internal(set) var additionalParams: [String: Encodable]? = nil
}
