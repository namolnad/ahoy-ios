import Combine
import Foundation

public final class Ahoy {
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

    /// Hooks for your application to modifiy the Ahoy requests prior to performing the request
    public var requestInterceptors: [RequestInterceptor]

    private let currentVisitSubject: CurrentValueSubject<Visit?, Error> = .init(nil)

    private let configuration: Configuration

    private let storage: AhoyTokenManager

    public init(
        configuration: Configuration,
        requestInterceptors: [RequestInterceptor] = [],
        storage: AhoyTokenManager? = nil
    ) {
        self.configuration = configuration
        self.requestInterceptors = requestInterceptors
        if storage == nil, let visitDuration = configuration.visitDuration {
            TokenManager.visitDuration = visitDuration
        }
        self.storage = storage ?? TokenManager()
    }

    public func trackVisit(additionalParams: [String: Encodable]? = nil) -> AnyPublisher<Visit, Error> {
        let visit: Visit = .init(
            visitorToken: storage.visitorToken,
            visitToken: storage.visitToken,
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

    public func track(events: [Event]) -> AnyPublisher<Void, Error> {
        guard let currentVisit = currentVisit else {
            return Fail(error: AhoyError.noVisit)
                .eraseToAnyPublisher()
        }

        let requestInput: EventRequestInput = .init(
            visitorToken: currentVisit.visitorToken,
            visitToken: currentVisit.visitToken,
            events: events
        )

        return dataTaskPublisher(
            path: configuration.eventsPath,
            body: requestInput,
            visit: currentVisit
        )
            .validateResponse()
            .map { _, _ in }
            .mapError { $0 }
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
        var events: [Event]
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
        var additionalParams: [String: Encodable]?

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
}
