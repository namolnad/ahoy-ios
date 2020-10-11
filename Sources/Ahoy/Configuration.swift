import Combine
import Foundation

@dynamicMemberLookup
public struct Configuration {
    public typealias URLRequestPublisher = AnyPublisher<URLSession.DataTaskPublisher.Output, URLSession.DataTaskPublisher.Failure>
    public typealias URLRequestHandler = (URLRequest) -> URLRequestPublisher

    public struct ApplicationEnvironment {
        var platform: String
        var appVersion: String
        var osVersion: String

        public init(platform: String, appVersion: String, osVersion: String) {
            self.platform = platform
            self.appVersion = appVersion
            self.osVersion = osVersion
        }
    }

    var environment: ApplicationEnvironment
    var urlRequestHandler: URLRequestHandler
    var baseUrl: URL
    var ahoyPath: String
    var eventsPath: String
    var visitsPath: String
    var visitDuration: TimeInterval?

    public init(
        environment: ApplicationEnvironment,
        urlRequestHandler: @escaping URLRequestHandler = { request in
            URLSession.shared.dataTaskPublisher(for: request).eraseToAnyPublisher()
        },
        baseUrl: URL,
        ahoyPath: String = "ahoy",
        eventsPath: String = "events",
        visitsPath: String = "visits",
        visitDuration: TimeInterval? = nil
    ) {
        self.environment = environment
        self.urlRequestHandler = urlRequestHandler
        self.baseUrl = baseUrl
        self.ahoyPath = ahoyPath
        self.eventsPath = eventsPath
        self.visitsPath = visitsPath
        self.visitDuration = visitDuration
    }

    subscript<T>(dynamicMember keyPath: KeyPath<ApplicationEnvironment, T>) -> T {
        environment[keyPath: keyPath]
    }
}
