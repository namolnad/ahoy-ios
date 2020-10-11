import Combine
import Foundation

public final class Ahoy {
    public var requestInterceptors: [RequestInterceptor]

    public private(set) lazy var currentVisit: Visit = .init(
        visitorToken: storage.visitorToken,
        visitToken: storage.visitToken
    )

    private static let jsonEncoder: JSONEncoder = {
        let encoder: JSONEncoder = .init()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

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

    public func trackVisit(additionalParams: [String: Encodable]? = nil) -> AnyPublisher<Void, Error> {
        currentVisit = .init(
            visitorToken: storage.visitorToken,
            visitToken: storage.visitToken,
            additionalParams: additionalParams
        )

        let requestInput: VisitRequestInput = .init(
            visitorToken: currentVisit.visitorToken,
            visitToken: currentVisit.visitToken,
            platform: configuration.platform,
            appVersion: configuration.appVersion,
            osVersion: configuration.osVersion,
            additionalParams: additionalParams
        )

        return dataTaskPublisher(path: configuration.visitsPath, body: requestInput)
            .validateResponse()
            .map { _, _ in }
            .eraseToAnyPublisher()
    }

    public func track(events: [Event]) -> AnyPublisher<Void, Error> {
        let requestInput: EventRequestInput = .init(
            visitorToken: currentVisit.visitorToken,
            visitToken: currentVisit.visitToken,
            events: events
        )

        return dataTaskPublisher(path: configuration.eventsPath, body: requestInput)
            .validateResponse()
            .map { _, _ in }
            .mapError { $0 }
            .eraseToAnyPublisher()
    }

    private func dataTaskPublisher<Body: Encodable>(path: String, body: Body) -> Configuration.URLRequestPublisher {
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
            "Ahoy-Visitor": currentVisit.visitorToken,
            "Ahoy-Visit": currentVisit.visitToken
        ]

        ahoyHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        return configuration.urlRequestHandler(request)
    }

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
