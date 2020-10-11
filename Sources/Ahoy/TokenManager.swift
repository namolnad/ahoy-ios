import Foundation

public protocol AhoyTokenManager {
    var visitorToken: String { get }
    var visitToken: String { get }
}

final class TokenManager: AhoyTokenManager {
    /// Defaults to 30 minutes
    static var visitDuration: TimeInterval = .thirtyMinutes

    private static let jsonEncoder: JSONEncoder = .init()

    private static let jsonDecoder: JSONDecoder = .init()

    /// Value will rotate according to the visitDuration
    @ExpiringPersisted(
        key: "ahoy_visit_token",
        newValue: { Current.uuid().uuidString },
        expiryPeriod: TokenManager.visitDuration,
        jsonEncoder: jsonEncoder,
        jsonDecoder: jsonDecoder
    )
    var visitToken: String

    /// Unchanging value
    @ExpiringPersisted(
        key: "ahoy_visitor_token",
        newValue: { Current.visitorToken().uuidString },
        jsonEncoder: jsonEncoder,
        jsonDecoder: jsonDecoder
    )
    var visitorToken: String
}


extension TimeInterval {
    fileprivate static let thirtyMinutes: TimeInterval = 1_800
}
