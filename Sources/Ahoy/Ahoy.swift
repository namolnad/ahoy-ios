import Combine
import Foundation

public final class Ahoy: @unchecked Sendable {
    /// The currently registered visit. Nil until a visit has been confirmed with your server
    public var currentVisit: Visit? {
        currentVisitSubject.value
    }

    /// A convenience access point for your application to get Ahoy headers for the current visit
    public var headers: [String: String] {
        guard let visit = currentVisit else { return [:] }

        return [
            "Ahoy-Visitor": visit.visitorToken,
            "Ahoy-Visit": visit.visitToken
        ]
    }

    /// A publisher to allow your application to listen for changes to the `currentVisit`
    public var currentVisitPublisher: AnyPublisher<Visit, Error> {
        currentVisitSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    /// Hooks for your application to modify the Ahoy requests prior to performing the request
    public var requestInterceptors: [RequestInterceptor] {
        get { withLock { _requestInterceptors } }
        set { withLock { _requestInterceptors = newValue } }
    }

    private let currentVisitSubject: CurrentValueSubject<Visit?, Error> = .init(nil)

    private let configuration: Configuration

    private let storage: AhoyTokenManager

    /// Guards every mutable property below, so that an `Ahoy` client can be shared across isolation domains
    private let lock: NSLock = .init()

    private var _requestInterceptors: [RequestInterceptor]

    private var _cancellables: Set<AnyCancellable> = []

    private var _attachedUserId: String?

    /// Retained across visits so that a user attached via `attach(userId:)` survives visit renewal
    private var attachedUserId: String? {
        get { withLock { _attachedUserId } }
        set { withLock { _attachedUserId = newValue } }
    }

    public init(
        configuration: Configuration,
        requestInterceptors: [RequestInterceptor] = [],
        storage: AhoyTokenManager? = nil
    ) {
        self.configuration = configuration
        self._requestInterceptors = requestInterceptors
        if let storage = storage {
            self.storage = storage
        } else if let visitDuration = configuration.visitDuration {
            self.storage = TokenManager(visitDuration: visitDuration)
        } else {
            self.storage = TokenManager()
        }

        if configuration.automaticVisitRenewal {
            observeApplicationBecomingActive()
        }
    }

    /// Tracks a visit. Can be called multiple times during a session—a new visit will be created as determined by your `TokenManager`.
    /// Calling this is only required when you have disabled `automaticVisitRenewal`, or when you wish to supply
    /// `additionalParams` for a specific visit.
    public func trackVisit(additionalParams: [String: any Encodable & Sendable]? = nil) -> AnyPublisher<Visit, Error> {
        let visit: Visit = .init(
            visitorToken: storage.visitorToken,
            visitToken: storage.visitToken,
            userId: attachedUserId,
            additionalParams: additionalParams
        )

        let requestInput: VisitRequestInput = .init(
            visitorToken: visit.visitorToken,
            visitToken: visit.visitToken,
            platform: configuration.platform,
            appVersion: configuration.appVersion,
            osVersion: configuration.osVersion,
            additionalParams: additionalParams
        )

        return dataTaskPublisher(
            path: configuration.visitsPath,
            body: requestInput,
            visit: visit
        )
            .validateResponse()
            .map { $0.0 }
            .decode(type: Visit.self, decoder: Self.jsonDecoder)
            .tryMap { visitResponse -> Visit in
                guard
                    visit.visitorToken == visitResponse.visitorToken,
                    visit.visitToken == visitResponse.visitToken
                else {
                    throw AhoyError.mismatchingVisit
                }
                // Pass back the visit created by the client (which has custom variables)
                return visit
            }
            .handleEvents(receiveOutput: { [weak self] visit in
                self?.currentVisitSubject.send(visit)
            })
            .eraseToAnyPublisher()
    }

    /// Returns the current visit, registering a new one when the stored visit token has expired or has yet to be
    /// confirmed with your server. This mirrors ahoy.js, which creates a visit on page load and lazily whenever an
    /// event is tracked after the visit cookie has lapsed.
    public func ensureCurrentVisit() -> AnyPublisher<Visit, Error> {
        // `hasValidVisitToken` must be consulted first: reading an expired `visitToken` mints a replacement.
        if let visit = currentVisit, storage.hasValidVisitToken, visit.visitToken == storage.visitToken {
            return Just(visit)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }

        return trackVisit(additionalParams: configuration.visitParams())
    }

    /// Bulk-tracking events
    public func track(events: [Event]) -> AnyPublisher<Void, Error> {
        visitForTracking()
            .flatMap { [weak self] visit -> AnyPublisher<Void, Error> in
                guard let self = self else {
                    return Fail(error: AhoyError.noVisit).eraseToAnyPublisher()
                }
                return self.send(events: events, visit: visit)
            }
            .eraseToAnyPublisher()
    }

    /// A fire-and-forget convenience function for tracking a single event
    public func track(_ eventName: String, properties: [String: any Encodable & Sendable] = [:]) {
        let cancellable = track(events: [.init(name: eventName, properties: properties)])
            .retry(3)
            .sink(receiveCompletion: { _ in }, receiveValue: {})

        store(cancellable)
    }

    /// Attaches a User's ID to be encoded as a root key within subsequent event JSON payloads. NOTE: This does not authenticate the user on your server and is only useful for specially-handled cases.
    /// Example event payload `{"properties":{"123":456},"user_id":"12345","name":"test","time":"1970-01-01T00:00:00Z"}`
    /// The attachment persists across visit renewals until `detachUser()` is called.
    public func attach(userId: String) {
        attachedUserId = userId
        var currentVisit = currentVisitSubject.value
        currentVisit?.userId = userId
        currentVisitSubject.send(currentVisit)
    }

    /// Clears a user previously attached with `attach(userId:)`, e.g. on sign-out.
    public func detachUser() {
        attachedUserId = nil
        var currentVisit = currentVisitSubject.value
        currentVisit?.userId = nil
        currentVisitSubject.send(currentVisit)
    }

    /// Renews the visit whenever the application becomes active — the platform's analogue of a web page load.
    private func observeApplicationBecomingActive() {
        guard let notificationName = Current.didBecomeActiveNotification else { return }

        let cancellable = Current.notificationCenter
            .publisher(for: notificationName)
            // `.max(1)` so that a burst of activations can't pile up overlapping visit requests
            .flatMap(maxPublishers: .max(1)) { [weak self] _ -> AnyPublisher<Visit, Never> in
                guard let self = self else {
                    return Empty().eraseToAnyPublisher()
                }
                // A no-op when the visit is still current
                return self.ensureCurrentVisit()
                    .catch { _ in Empty<Visit, Never>() }
                    .eraseToAnyPublisher()
            }
            .sink { _ in }

        store(cancellable)
    }

    private func withLock<R>(_ body: () -> R) -> R {
        lock.lock()
        defer { lock.unlock() }

        return body()
    }

    private func store(_ cancellable: AnyCancellable) {
        withLock { _ = _cancellables.insert(cancellable) }
    }

    private func visitForTracking() -> AnyPublisher<Visit, Error> {
        guard configuration.automaticVisitRenewal else {
            return currentVisit.map {
                Just($0).setFailureType(to: Error.self).eraseToAnyPublisher()
            } ?? Fail(error: AhoyError.noVisit).eraseToAnyPublisher()
        }

        return ensureCurrentVisit()
    }

    private func send(events: [Event], visit: Visit) -> AnyPublisher<Void, Error> {
        let requestInput: EventRequestInput = .init(
            visitorToken: visit.visitorToken,
            visitToken: visit.visitToken,
            events: events.map { .init(userId: visit.userId, wrapped: $0) }
        )

        return dataTaskPublisher(
            path: configuration.eventsPath,
            body: requestInput,
            visit: visit
        )
            .validateResponse()
            .map { _, _ in }
            .eraseToAnyPublisher()
    }

    private func dataTaskPublisher<Body: Encodable>(path: String, body: Body, visit: Visit) -> Configuration.URLRequestPublisher {
        var request: URLRequest = .init(
            url: configuration.baseUrl
                .appendingPathComponent(configuration.ahoyPath)
                .appendingPathComponent(path)
        )
        request.httpBody = try? Self.jsonEncoder.encode(body)
        request.httpMethod = "POST"

        requestInterceptors.forEach { $0.interceptRequest(&request) }

        let ahoyHeaders: [String: String] = [
            "Content-Type": " application/json; charset=utf-8",
            "Ahoy-Visitor": visit.visitorToken,
            "Ahoy-Visit": visit.visitToken
        ]

        ahoyHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        return configuration.urlRequestHandler(request)
    }

    private static let jsonEncoder: JSONEncoder = {
        let encoder: JSONEncoder = .init()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let jsonDecoder: JSONDecoder = {
        let decoder: JSONDecoder = .init()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private struct EventRequestInput: Encodable {
        var visitorToken: String
        var visitToken: String
        var events: [UserIdDecorated<Event>]
    }

    private struct VisitRequestInput: Encodable {
        private enum CodingKeys: CodingKey {
            case visitorToken
            case visitToken
            case platform
            case appVersion
            case osVersion
            case custom(String)

            var stringValue: String {
                switch self {
                case .appVersion:
                    return "appVersion"
                case .osVersion:
                    return "osVersion"
                case .platform:
                    return "platform"
                case .visitToken:
                    return "visitToken"
                case .visitorToken:
                    return "visitorToken"
                case let .custom(value):
                    return value
                }
            }

            init?(stringValue: String) {
                switch stringValue {
                case "appVersion":
                    self = .appVersion
                case "osVersion":
                    self = .osVersion
                case "platform":
                    self = .platform
                case "visitToken":
                    self = .visitToken
                case "visitorToken":
                    self = .visitorToken
                default:
                    self = .custom(stringValue)
                }
            }

            var intValue: Int? { nil }

            init?(intValue: Int) { nil }
        }

        var visitorToken: String
        var visitToken: String
        var platform: String
        var appVersion: String
        var osVersion: String
        var additionalParams: [String: any Encodable & Sendable]?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(visitorToken, forKey: .visitorToken)
            try container.encode(visitToken, forKey: .visitToken)
            try container.encode(platform, forKey: .platform)
            try container.encode(appVersion, forKey: .appVersion)
            try container.encode(osVersion, forKey: .osVersion)
            try additionalParams?.sorted(by: { $0.0 < $1.0 }).forEach { key, value in
                let wrapper = AnyEncodable(wrapped: value)
                try container.encode(wrapper, forKey: .custom(key))
            }
        }
    }

    private struct UserIdDecorated<Wrapped: Encodable>: Encodable {
        enum CodingKeys: CodingKey {
            case userId
        }

        let userId: String?
        let wrapped: Wrapped

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(userId, forKey: .userId)
            try wrapped.encode(to: encoder)
        }
    }
}
