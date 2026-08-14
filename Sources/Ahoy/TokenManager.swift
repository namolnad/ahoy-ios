import Foundation

public protocol AhoyTokenManager: Sendable {
    var visitorToken: String { get }
    var visitToken: String { get }
    /// Whether the manager currently holds an unexpired visit token. When `false`, reading `visitToken`
    /// is expected to mint a fresh one, which in turn requires a new visit to be registered with your server.
    var hasValidVisitToken: Bool { get }
}

public extension AhoyTokenManager {
    /// Managers which don't express an expiry are always considered valid, leaving visit creation entirely to your application.
    var hasValidVisitToken: Bool { true }
}

/// Unchecked because the property wrappers below hold their own lock; see `ExpiringPersisted`
final class TokenManager: AhoyTokenManager, @unchecked Sendable {
    private static let jsonEncoder: JSONEncoder = .init()

    private static let jsonDecoder: JSONDecoder = .init()

    /// Value will rotate according to the visitDuration
    @ExpiringPersisted var visitToken: String

    /// Unchanging value
    @ExpiringPersisted var visitorToken: String

    var hasValidVisitToken: Bool {
        $visitToken
    }

    init(visitDuration: TimeInterval = .defaultVisitDuration) {
        _visitToken = .init(
            key: "ahoy_visit_token",
            newValue: { Current.uuid().uuidString },
            expiryPeriod: visitDuration,
            jsonEncoder: Self.jsonEncoder,
            jsonDecoder: Self.jsonDecoder
        )
        _visitorToken = .init(
            key: "ahoy_visitor_token",
            newValue: { Current.visitorToken().uuidString },
            jsonEncoder: Self.jsonEncoder,
            jsonDecoder: Self.jsonDecoder
        )
    }
}

extension TimeInterval {
    /// Four hours, matching ahoy.js's `visitDuration` and the Ahoy gem's `Ahoy.visit_duration`
    public static let defaultVisitDuration: TimeInterval = 14_400
}
