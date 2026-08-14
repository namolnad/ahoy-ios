import Combine
import Foundation

@dynamicMemberLookup
public struct Configuration: Sendable {
    public typealias URLRequestPublisher = AnyPublisher<URLSession.DataTaskPublisher.Output, URLSession.DataTaskPublisher.Failure>
    public typealias URLRequestHandler = @Sendable (URLRequest) -> URLRequestPublisher
    public typealias VisitParamsProvider = @Sendable () -> [String: any Encodable & Sendable]?

    public struct ApplicationEnvironment: Sendable {
        let platform: String
        let appVersion: String
        let osVersion: String

        public init(platform: String, appVersion: String, osVersion: String) {
            self.platform = platform
            self.appVersion = appVersion
            self.osVersion = osVersion
        }
    }

    let environment: ApplicationEnvironment
    let urlRequestHandler: URLRequestHandler
    let baseUrl: URL
    let ahoyPath: String
    let eventsPath: String
    let visitsPath: String
    let visitDuration: TimeInterval?
    let automaticVisitRenewal: Bool
    let visitParams: VisitParamsProvider

    /// - Parameters:
    ///   - visitDuration: How long a visit remains valid, measured from its creation. Defaults to four hours,
    ///     matching ahoy.js and the Ahoy gem's `Ahoy.visit_duration`.
    ///   - automaticVisitRenewal: When enabled (the default), Ahoy registers a new visit whenever the current one
    ///     has expired — both when your application becomes active and lazily when you track an event. Disable this
    ///     to take full control of visit creation via `trackVisit`.
    ///   - visitParams: Supplies the params — utm parameters, referrer, etc. — for visits Ahoy creates on your
    ///     behalf during automatic renewal. Ignored for visits you track yourself via `trackVisit(additionalParams:)`.
    public init(
        environment: ApplicationEnvironment,
        urlRequestHandler: @escaping URLRequestHandler = { request in
            URLSession.shared.dataTaskPublisher(for: request).eraseToAnyPublisher()
        },
        baseUrl: URL,
        ahoyPath: String = "ahoy",
        eventsPath: String = "events",
        visitsPath: String = "visits",
        visitDuration: TimeInterval? = nil,
        automaticVisitRenewal: Bool = true,
        visitParams: @escaping VisitParamsProvider = { nil }
    ) {
        self.environment = environment
        self.urlRequestHandler = urlRequestHandler
        self.baseUrl = baseUrl
        self.ahoyPath = ahoyPath
        self.eventsPath = eventsPath
        self.visitsPath = visitsPath
        self.visitDuration = visitDuration
        self.automaticVisitRenewal = automaticVisitRenewal
        self.visitParams = visitParams
    }

    public subscript<T>(dynamicMember keyPath: KeyPath<ApplicationEnvironment, T>) -> T {
        environment[keyPath: keyPath]
    }
}
