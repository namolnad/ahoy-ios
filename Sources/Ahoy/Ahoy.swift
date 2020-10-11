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

    public func trackVisit() -> AnyPublisher<Void, Error> {
        currentVisit = .init(
            visitorToken: storage.visitorToken,
            visitToken: storage.visitToken
        )

        let requestInput: VisitRequestInput = .init(
            visitorToken: currentVisit.visitorToken,
            visitToken: currentVisit.visitToken,
            platform: configuration.platform,
            appVersion: configuration.appVersion,
            osVersion: configuration.osVersion
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
        request.allHTTPHeaderFields = [
            "Content-Type": " application/json; charset=utf-8",
            "Ahoy-Visitor": currentVisit.visitorToken,
            "Ahoy-Visit": currentVisit.visitToken
        ]

        requestInterceptors.forEach { $0.interceptRequest(&request) }

        return configuration.urlRequestHandler(request)
    }

    private struct EventRequestInput: Encodable {
        var visitorToken: String
        var visitToken: String
        var events: [Event]
    }

    private struct VisitRequestInput: Encodable {
        var visitorToken: String
        var visitToken: String
        var platform: String
        var appVersion: String
        var osVersion: String
    }
}
