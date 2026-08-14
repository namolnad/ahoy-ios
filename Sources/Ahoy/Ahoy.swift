import Foundation

public actor Ahoy {
    /// The currently registered visit. Nil until a visit has been confirmed with your server
    public private(set) var currentVisit: Visit?

    /// A convenience access point for your application to get Ahoy headers for the current visit
    public var headers: [String: String] {
        guard let visit = currentVisit else { return [:] }

        return [
            "Ahoy-Visitor": visit.visitorToken,
            "Ahoy-Visit": visit.visitToken
        ]
    }

    /// Hooks for your application to modify the Ahoy requests prior to performing the request
    public private(set) var requestInterceptors: [RequestInterceptor]

    /// Each newly registered visit, beginning with the current one if there is one.
    /// Every call returns an independent sequence, so several observers can iterate at once.
    public nonisolated var visits: AsyncStream<Visit> {
        let id: UUID = .init()

        return AsyncStream { continuation in
            Task { await self.addVisitObserver(id: id, continuation: continuation) }

            continuation.onTermination = { _ in
                Task { await self.removeVisitObserver(id: id) }
            }
        }
    }

    private let configuration: Configuration

    private let storage: AhoyTokenManager

    /// Retained across visits so that a user attached via `attach(userId:)` survives visit renewal
    private var attachedUserId: String?

    /// The visit request currently in flight, shared by every caller that arrives while it runs
    private var pendingVisit: Task<Visit, Error>?

    private var visitObservers: [UUID: AsyncStream<Visit>.Continuation] = [:]

    private var lifecycleTask: Task<Void, Never>?

    public init(
        configuration: Configuration,
        requestInterceptors: [RequestInterceptor] = [],
        storage: AhoyTokenManager? = nil
    ) {
        self.configuration = configuration
        self.requestInterceptors = requestInterceptors
        if let storage = storage {
            self.storage = storage
        } else if let visitDuration = configuration.visitDuration {
            self.storage = TokenManager(visitDuration: visitDuration)
        } else {
            self.storage = TokenManager()
        }

        if configuration.automaticVisitRenewal {
            Task { await self.observeApplicationBecomingActive() }
        }
    }

    deinit {
        lifecycleTask?.cancel()
        visitObservers.values.forEach { $0.finish() }
    }

    /// Tracks a visit. Can be called multiple times during a session—a new visit will be created as determined by your `TokenManager`.
    /// Calling this is only required when you have disabled `automaticVisitRenewal`, or when you wish to supply
    /// `additionalParams` for a specific visit.
    @discardableResult
    public func trackVisit(additionalParams: [String: any Encodable & Sendable]? = nil) async throws -> Visit {
        try await performTrackVisit(additionalParams: additionalParams)
    }

    /// Returns the current visit, registering a new one when the stored visit token has expired or has yet to be
    /// confirmed with your server. This mirrors ahoy.js, which creates a visit on page load and lazily whenever an
    /// event is tracked after the visit cookie has lapsed.
    ///
    /// Callers arriving while a visit request is already in flight await that same request rather than starting another.
    @discardableResult
    public func ensureCurrentVisit() async throws -> Visit {
        // `hasValidVisitToken` must be consulted first: reading an expired `visitToken` mints a replacement.
        if let visit = currentVisit, storage.hasValidVisitToken, visit.visitToken == storage.visitToken {
            return visit
        }

        if let pendingVisit = pendingVisit {
            return try await pendingVisit.value
        }

        let additionalParams = configuration.visitParams()
        // Assigned before the first suspension below, so a reentrant caller finds it rather than starting its own
        let task: Task<Visit, Error> = Task { try await self.performTrackVisit(additionalParams: additionalParams) }
        pendingVisit = task

        let result = await task.result
        pendingVisit = nil

        return try result.get()
    }

    /// Bulk-tracking events
    public func track(events: [Event]) async throws {
        let visit = try await visitForTracking()

        let requestInput: EventRequestInput = .init(
            visitorToken: visit.visitorToken,
            visitToken: visit.visitToken,
            events: events.map { .init(userId: visit.userId, wrapped: $0) }
        )

        let (data, response) = try await perform(
            path: configuration.eventsPath,
            body: requestInput,
            visit: visit
        )

        try validate(data: data, response: response)
    }

    /// A fire-and-forget convenience function for tracking a single event. Callable from anywhere—the event is
    /// timestamped immediately and delivered on a detached task, retrying a few times before giving up.
    public nonisolated func track(_ eventName: String, properties: [String: any Encodable & Sendable] = [:]) {
        let event: Event = .init(name: eventName, properties: properties)

        Task { await self.trackDiscardingErrors(event) }
    }

    /// Attaches a User's ID to be encoded as a root key within subsequent event JSON payloads. NOTE: This does not authenticate the user on your server and is only useful for specially-handled cases.
    /// Example event payload `{"properties":{"123":456},"user_id":"12345","name":"test","time":"1970-01-01T00:00:00Z"}`
    /// The attachment persists across visit renewals until `detachUser()` is called.
    public func attach(userId: String) {
        attachedUserId = userId

        if var visit = currentVisit {
            visit.userId = userId
            update(currentVisit: visit)
        }
    }

    /// Clears a user previously attached with `attach(userId:)`, e.g. on sign-out.
    public func detachUser() {
        attachedUserId = nil

        if var visit = currentVisit {
            visit.userId = nil
            update(currentVisit: visit)
        }
    }

    /// Replaces the interceptors applied to subsequent Ahoy requests
    public func setRequestInterceptors(_ interceptors: [RequestInterceptor]) {
        requestInterceptors = interceptors
    }

    private func trackDiscardingErrors(_ event: Event) async {
        for attempt in 0...Self.trackRetryCount {
            do {
                return try await track(events: [event])
            } catch {
                if attempt == Self.trackRetryCount { return }
            }
        }
    }

    private func visitForTracking() async throws -> Visit {
        guard configuration.automaticVisitRenewal else {
            guard let currentVisit = currentVisit else { throw AhoyError.noVisit }

            return currentVisit
        }

        return try await ensureCurrentVisit()
    }

    private func performTrackVisit(additionalParams: [String: any Encodable & Sendable]?) async throws -> Visit {
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

        let (data, response) = try await perform(
            path: configuration.visitsPath,
            body: requestInput,
            visit: visit
        )

        try validate(data: data, response: response)

        let visitResponse = try Self.jsonDecoder.decode(Visit.self, from: data)

        guard
            visit.visitorToken == visitResponse.visitorToken,
            visit.visitToken == visitResponse.visitToken
        else {
            throw AhoyError.mismatchingVisit
        }

        // Keep the visit created by the client, which carries the custom variables
        update(currentVisit: visit)

        return visit
    }

    private func perform<Body: Encodable>(path: String, body: Body, visit: Visit) async throws -> (Data, URLResponse) {
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

        return try await configuration.urlRequestHandler(request)
    }

    /// Renews the visit whenever the application becomes active — the platform's analogue of a web page load.
    private func observeApplicationBecomingActive() {
        guard let notificationName = Current.didBecomeActiveNotification else { return }

        let activations = ApplicationLifecycle.activations(named: notificationName)

        // Serial by construction: the next activation is not read until this one is handled
        lifecycleTask = Task { [weak self] in
            for await _ in activations {
                // A no-op when the visit is still current
                _ = try? await self?.ensureCurrentVisit()
            }
        }
    }

    private func update(currentVisit visit: Visit) {
        currentVisit = visit
        visitObservers.values.forEach { $0.yield(visit) }
    }

    private func addVisitObserver(id: UUID, continuation: AsyncStream<Visit>.Continuation) {
        visitObservers[id] = continuation

        // Replays the current visit, matching the behavior observers relied on previously
        if let currentVisit = currentVisit {
            continuation.yield(currentVisit)
        }
    }

    private func removeVisitObserver(id: UUID) {
        visitObservers.removeValue(forKey: id)
    }

    /// Attempts beyond the first, for fire-and-forget tracking
    private static let trackRetryCount = 3

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
