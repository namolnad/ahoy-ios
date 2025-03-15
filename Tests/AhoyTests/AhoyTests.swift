import Combine
#if !os(watchOS)
import XCTest
#endif
@testable import Ahoy

#if !os(watchOS)
@available(iOS 13, tvOS 13, macOS 10.15, *)
final class AhoyTests: XCTestCase {
    private var ahoy: Ahoy!

    private let configuration: Configuration = .testDefault

    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()

        ahoy = .init(configuration: configuration)
        TestDefaults.instance.reset()
        Current.defaults = TestDefaults.instance
        Current.visitorToken = { UUID(uuidString: "EB4DCB73-2B32-52CD-A2CF-AD7948674B22")! }
    }

    func testTrackVisit() {
        XCTAssertNil(ahoy.currentVisit)

        Current.date = { .init(timeIntervalSince1970: 0) }
        Current.uuid = { UUID(uuidString: "B054681C-100B-46FE-94A0-7AACA78116CB")! }

        let configuration = self.configuration

        var testHeaders: [String: String] = [
            "Ahoy-Visit": "B054681C-100B-46FE-94A0-7AACA78116CB",
            "Ahoy-Visitor": "EB4DCB73-2B32-52CD-A2CF-AD7948674B22",
            "Content-Type": " application/json; charset=utf-8"
        ]

        var expectedRequestBody: String = "{\"app_version\":\"9.9.99\",\"os_version\":\"16.0.2\",\"platform\":\"iOS\",\"visit_token\":\"B054681C-100B-46FE-94A0-7AACA78116CB\",\"visitor_token\":\"EB4DCB73-2B32-52CD-A2CF-AD7948674B22\"}"

        let expectation1 = self.expectation(description: "1")

        ahoy.trackVisit()
            .sink(
                receiveCompletion: { if case .failure = $0 { XCTFail() } },
                receiveValue: { _ in
                    XCTAssertEqual(TestRequestHandler.instance.headers, testHeaders)
                    XCTAssertEqual(TestRequestHandler.instance.body, expectedRequestBody)
                    XCTAssertEqual(TestRequestHandler.instance.url.absoluteString, "https://ahoy.com/test-ahoy/my-visits")
                    expectation1.fulfill()
                }
            )
            .store(in: &cancellables)

        wait(for: [expectation1], timeout: 0.1)

        XCTAssertEqual(ahoy.headers["Ahoy-Visitor"], "EB4DCB73-2B32-52CD-A2CF-AD7948674B22")

        Current.date = { Date(timeIntervalSince1970: 0).advanced(by: configuration.visitDuration! - 1) }
        Current.uuid = { UUID(uuidString: "4D02659F-6030-4C9A-B63F-9E322127C42B")! }

        expectedRequestBody = "{\"app_version\":\"9.9.99\",\"os_version\":\"16.0.2\",\"platform\":\"iOS\",\"source\":3,\"utm_source\":\"some-place\",\"visit_token\":\"B054681C-100B-46FE-94A0-7AACA78116CB\",\"visitor_token\":\"EB4DCB73-2B32-52CD-A2CF-AD7948674B22\"}"

        let expectation2 = self.expectation(description: "2")

        ahoy.trackVisit(additionalParams: ["utm_source": "some-place", "source": 3])
            .sink(
                receiveCompletion: { if case .failure = $0 { XCTFail() } },
                receiveValue: { _ in
                    XCTAssertEqual(TestRequestHandler.instance.body, expectedRequestBody)
                    XCTAssertEqual(TestRequestHandler.instance.headers, testHeaders)
                    expectation2.fulfill()
                }
            )
            .store(in: &cancellables)

        wait(for: [expectation2], timeout: 0.1)

        XCTAssertEqual(ahoy.headers["Ahoy-Visitor"], "EB4DCB73-2B32-52CD-A2CF-AD7948674B22")
        XCTAssertEqual(ahoy.currentVisit!.visitToken, "B054681C-100B-46FE-94A0-7AACA78116CB")
        XCTAssertEqual(ahoy.headers["Ahoy-Visit"], "B054681C-100B-46FE-94A0-7AACA78116CB")

        Current.date = { Date(timeIntervalSince1970: 0).advanced(by: configuration.visitDuration! + 10) }
        ahoy.requestInterceptors = [
            .init { $0.addValue("intercepted", forHTTPHeaderField: "intercept-test")}
        ]

        testHeaders["Ahoy-Visit"] = "4D02659F-6030-4C9A-B63F-9E322127C42B"
        testHeaders["intercept-test"] = "intercepted"

        let expectation3 = self.expectation(description: "3")

        ahoy.trackVisit()
            .sink(
                receiveCompletion: { if case .failure = $0 { XCTFail() } },
                receiveValue: { _ in
                    XCTAssertEqual(TestRequestHandler.instance.headers, testHeaders)
                    expectation3.fulfill()
                }
            )
            .store(in: &cancellables)

        wait(for: [expectation3], timeout: 0.1)

        XCTAssertEqual(ahoy.currentVisit!.visitToken, "4D02659F-6030-4C9A-B63F-9E322127C42B")
        XCTAssertEqual(ahoy.headers["Ahoy-Visit"], "4D02659F-6030-4C9A-B63F-9E322127C42B")

    }

    func testTrackEvents() {
        let expectedRequestBody: String = "{\"events\":[{\"name\":\"test\",\"properties\":{\"123\":456},\"time\":\"1970-01-01T00:00:00Z\"}],\"visit_token\":\"98C44594-050F-4DEF-80AF-AB723472469B\",\"visitor_token\":\"EB4DCB73-2B32-52CD-A2CF-AD7948674B22\"}"

        Current.uuid = { UUID(uuidString: "98C44594-050F-4DEF-80AF-AB723472469B")! }

        let visitExpectation = self.expectation(description: "visit")

        ahoy.trackVisit()
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in
                visitExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [visitExpectation], timeout: 0.1)

        let events: [Event] = [
            .init(name: "test", properties: ["123": 456], time: .init(timeIntervalSince1970: 0))
        ]

        let expectation = self.expectation(description: "track_events")

        ahoy.track(events: events)
            .sink(
                receiveCompletion: { if case .failure = $0 { XCTFail() } },
                receiveValue: {
                    XCTAssertEqual(TestRequestHandler.instance.body, expectedRequestBody)
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 0.1)
    }

    func testTrackEventsWithAttachedUser() {
        let expectedRequestBody: String = "{\"events\":[{\"name\":\"test\",\"properties\":{\"123\":456},\"time\":\"1970-01-01T00:00:00Z\",\"user_id\":\"12345\"}],\"visit_token\":\"98C44594-050F-4DEF-80AF-AB723472469B\",\"visitor_token\":\"EB4DCB73-2B32-52CD-A2CF-AD7948674B22\"}"

        Current.uuid = { UUID(uuidString: "98C44594-050F-4DEF-80AF-AB723472469B")! }

        let visitExpectation = self.expectation(description: "visit")

        ahoy.trackVisit()
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in
                visitExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [visitExpectation], timeout: 0.1)

        ahoy.attach(userId: "12345")

        let events: [Event] = [
            .init(name: "test", properties: ["123": 456], time: .init(timeIntervalSince1970: 0))
        ]

        let expectation = self.expectation(description: "track_events")

        ahoy.track(events: events)
            .sink(
                receiveCompletion: { if case .failure = $0 { XCTFail() } },
                receiveValue: {
                    XCTAssertEqual(TestRequestHandler.instance.body, expectedRequestBody)
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 0.1)
    }

    static var allTests = [
        ("testTrackVisit", testTrackVisit),
        ("testTrackEvents", testTrackEvents)
    ]
}

extension Configuration {
    static let testDefault: Self = .init(
        environment: .testDefault,
        urlRequestHandler: TestRequestHandler.instance.publisher(for:),
        baseUrl: URL(string: "https://ahoy.com")!,
        ahoyPath: "test-ahoy",
        eventsPath: "my-events",
        visitsPath: "my-visits",
        visitDuration: .oneHour
    )
}

extension Configuration.ApplicationEnvironment {
    static let testDefault: Self = .init(
        platform: "iOS",
        appVersion: "9.9.99",
        osVersion: "16.0.2"
    )
}

extension Optional where Wrapped == TimeInterval {
    static let oneHour: TimeInterval = 3_600
}

final class TestRequestHandler {
    var headers: [String: String]!
    var body: String!
    var url: URL!

    func publisher(for urlRequest: URLRequest) -> Configuration.URLRequestPublisher {
        headers = urlRequest.allHTTPHeaderFields
        body = String(data: urlRequest.httpBody!, encoding: .utf8)
        url = urlRequest.url

        return Just(
            (
                urlRequest.httpBody!,
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: "1.0", headerFields: headers)!
            )
        )
            .setFailureType(to: URLError.self)
            .eraseToAnyPublisher()
    }
}

extension TestRequestHandler {
    static let instance: TestRequestHandler = .init()
}

final class TestDefaults: UserDefaults {
    static let instance: TestDefaults = .init()

    private var storage: [String: Any] = [:]

    override func set(_ value: Any?, forKey key: String) {
        storage[key] = value
    }

    override func value(forKey key: String) -> Any? {
        storage[key]
    }

    func reset() {
        storage = [:]
    }
}
#endif
