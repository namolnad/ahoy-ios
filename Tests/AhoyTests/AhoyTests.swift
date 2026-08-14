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

        Current = .init()
        TestDefaults.instance.reset()
        TestRequestHandler.instance.reset()
        Current.defaults = TestDefaults.instance
        Current.date = { .init(timeIntervalSince1970: 0) }
        Current.visitorToken = { UUID(uuidString: "EB4DCB73-2B32-52CD-A2CF-AD7948674B22")! }
        Current.didBecomeActiveNotification = .init("ahoy_test_did_become_active")
        Current.notificationCenter = .init()

        ahoy = .init(configuration: configuration)
    }

    override func tearDown() {
        cancellables.removeAll()

        super.tearDown()
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

    // MARK: - Automatic visit renewal

    /// The heart of https://github.com/namolnad/ahoy-ios/issues/4: events tracked after the visit has lapsed must
    /// land on a fresh visit rather than the stale one captured at launch — as ahoy.js does on the web.
    func testEventTrackingRenewsExpiredVisit() {
        Current.uuid = { .firstToken }

        trackVisitAndWait(on: ahoy)

        XCTAssertEqual(ahoy.currentVisit?.visitToken, UUID.firstToken.uuidString)

        advancePastVisitDuration()
        Current.uuid = { .secondToken }

        trackEventAndWait(on: ahoy, named: "after_expiry")

        XCTAssertEqual(ahoy.currentVisit?.visitToken, UUID.secondToken.uuidString)
        XCTAssertEqual(TestRequestHandler.instance.headers["Ahoy-Visit"], UUID.secondToken.uuidString)
        XCTAssertTrue(TestRequestHandler.instance.body.contains("\"visit_token\":\"\(UUID.secondToken.uuidString)\""))
        XCTAssertTrue(TestRequestHandler.instance.body.contains("after_expiry"))
    }

    func testEventTrackingReusesUnexpiredVisit() {
        Current.uuid = { .firstToken }

        trackVisitAndWait(on: ahoy)

        let requestsAfterVisit = TestRequestHandler.instance.requestCount

        let visitDuration = configuration.visitDuration!
        Current.date = { Date(timeIntervalSince1970: 0).advanced(by: visitDuration - 1) }
        Current.uuid = { .secondToken }

        trackEventAndWait(on: ahoy, named: "within_duration")

        XCTAssertEqual(ahoy.currentVisit?.visitToken, UUID.firstToken.uuidString)
        // Only the events request — no visit was registered
        XCTAssertEqual(TestRequestHandler.instance.requestCount, requestsAfterVisit + 1)
    }

    /// A visit no longer needs to be tracked by hand before events can be sent
    func testEventTrackingCreatesInitialVisit() {
        Current.uuid = { .firstToken }

        XCTAssertNil(ahoy.currentVisit)

        trackEventAndWait(on: ahoy, named: "no_prior_visit")

        XCTAssertEqual(ahoy.currentVisit?.visitToken, UUID.firstToken.uuidString)
        XCTAssertTrue(TestRequestHandler.instance.body.contains("no_prior_visit"))
    }

    func testBecomingActiveRenewsExpiredVisit() {
        Current.uuid = { .firstToken }

        trackVisitAndWait(on: ahoy)

        advancePastVisitDuration()
        Current.uuid = { .secondToken }

        postDidBecomeActive()

        XCTAssertEqual(ahoy.currentVisit?.visitToken, UUID.secondToken.uuidString)
    }

    func testBecomingActiveLeavesUnexpiredVisitAlone() {
        Current.uuid = { .firstToken }

        trackVisitAndWait(on: ahoy)

        let requestsAfterVisit = TestRequestHandler.instance.requestCount
        Current.uuid = { .secondToken }

        postDidBecomeActive()

        XCTAssertEqual(ahoy.currentVisit?.visitToken, UUID.firstToken.uuidString)
        XCTAssertEqual(TestRequestHandler.instance.requestCount, requestsAfterVisit)
    }

    func testRenewedVisitUsesConfiguredVisitParams() {
        Current.uuid = { .firstToken }

        let ahoy: Ahoy = .init(configuration: .visitParamsTestDefault)

        trackEventAndWait(on: ahoy, named: "renewed")

        XCTAssertEqual(
            TestRequestHandler.instance.visitRequestBody,
            "{\"app_version\":\"9.9.99\",\"os_version\":\"16.0.2\",\"platform\":\"iOS\",\"utm_source\":\"push\",\"visit_token\":\"\(UUID.firstToken.uuidString)\",\"visitor_token\":\"EB4DCB73-2B32-52CD-A2CF-AD7948674B22\"}"
        )
    }

    func testAttachedUserSurvivesVisitRenewal() {
        Current.uuid = { .firstToken }

        trackVisitAndWait(on: ahoy)
        ahoy.attach(userId: "12345")

        advancePastVisitDuration()
        Current.uuid = { .secondToken }

        trackEventAndWait(on: ahoy, named: "after_expiry")

        XCTAssertEqual(ahoy.currentVisit?.visitToken, UUID.secondToken.uuidString)
        XCTAssertEqual(ahoy.currentVisit?.userId, "12345")
        XCTAssertTrue(TestRequestHandler.instance.body.contains("\"user_id\":\"12345\""))
    }

    func testDetachUserClearsAttachment() {
        Current.uuid = { .firstToken }

        trackVisitAndWait(on: ahoy)
        ahoy.attach(userId: "12345")
        ahoy.detachUser()

        advancePastVisitDuration()
        Current.uuid = { .secondToken }

        trackEventAndWait(on: ahoy, named: "after_expiry")

        XCTAssertNil(ahoy.currentVisit?.userId)
        XCTAssertFalse(TestRequestHandler.instance.body.contains("user_id"))
    }

    // MARK: - Manual visit management

    func testManualRenewalFailsWithoutAVisit() {
        let manual: Ahoy = .init(configuration: .manualTestDefault)

        let expectation = self.expectation(description: "no_visit")

        manual.track(events: [.init(name: "test", properties: [:], time: .init(timeIntervalSince1970: 0))])
            .sink(
                receiveCompletion: { completion in
                    guard case let .failure(error) = completion, case AhoyError.noVisit = error else {
                        return XCTFail("Expected AhoyError.noVisit")
                    }
                    expectation.fulfill()
                },
                receiveValue: { XCTFail("Expected no value") }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 0.1)
    }

    func testManualRenewalKeepsExpiredVisit() {
        Current.uuid = { .firstToken }

        let manual: Ahoy = .init(configuration: .manualTestDefault)

        trackVisitAndWait(on: manual)

        advancePastVisitDuration()
        Current.uuid = { .secondToken }

        postDidBecomeActive()
        trackEventAndWait(on: manual, named: "after_expiry")

        XCTAssertEqual(manual.currentVisit?.visitToken, UUID.firstToken.uuidString)
    }

    // MARK: - Token persistence

    /// `visitorToken` carries no expiry period — it must survive repeated reads rather than being re-minted each time
    func testVisitorTokenIsStableAcrossReads() {
        let mints: Locked<Int> = .init(0)
        Current.visitorToken = {
            mints.mutate { $0 += 1 }
            return .firstToken
        }

        let manager: TokenManager = .init()

        let first = manager.visitorToken
        let second = manager.visitorToken
        let third = manager.visitorToken

        XCTAssertEqual(first, second)
        XCTAssertEqual(second, third)
        XCTAssertEqual(mints.current, 1)
    }

    /// Concurrent readers arriving at an expired token must agree on its replacement rather than each minting
    /// their own, which would scatter a single session's events across several visits
    func testConcurrentReadsMintASingleVisitToken() {
        let mints: Locked<Int> = .init(0)
        Current.uuid = {
            mints.mutate { $0 += 1 }
            return .init()
        }

        let manager: TokenManager = .init(visitDuration: 3_600)
        let tokens: Locked<Set<String>> = .init([])

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            let token = manager.visitToken
            tokens.mutate { $0.insert(token) }
        }

        XCTAssertEqual(tokens.current.count, 1)
        XCTAssertEqual(mints.current, 1)
    }

    func testVisitTokenValidityReflectsExpiry() {
        let manager: TokenManager = .init(visitDuration: 3_600)

        XCTAssertFalse(manager.hasValidVisitToken, "No token has been minted yet")

        _ = manager.visitToken

        XCTAssertTrue(manager.hasValidVisitToken)

        Current.date = { Date(timeIntervalSince1970: 0).advanced(by: 3_601) }

        XCTAssertFalse(manager.hasValidVisitToken)
    }

    // MARK: - Fire-and-forget bookkeeping

    /// The test handler completes synchronously, so each subscription settles before it can even be retained
    func testFireAndForgetTrackingReleasesSynchronousRequests() {
        Current.uuid = { .firstToken }

        for index in 0..<50 {
            ahoy.track("event_\(index)")
        }

        XCTAssertEqual(ahoy.inFlightEventCount, 0)
        XCTAssertEqual(ahoy.settledEventCount, 0, "Bookkeeping must drain rather than trade one leak for another")
        XCTAssertTrue(TestRequestHandler.instance.body.contains("event_49"))
    }

    func testFireAndForgetTrackingReleasesDeferredRequests() {
        Current.uuid = { .firstToken }
        DeferredEventsRequestHandler.instance.reset()

        let ahoy: Ahoy = .init(configuration: .deferredEventsTestDefault)

        ahoy.track("deferred_one")
        ahoy.track("deferred_two")

        XCTAssertEqual(ahoy.inFlightEventCount, 2, "Both requests are still in flight")

        DeferredEventsRequestHandler.instance.completePending()

        XCTAssertEqual(ahoy.inFlightEventCount, 0)
        XCTAssertEqual(ahoy.settledEventCount, 0)
    }

    // MARK: - Concurrency

    /// Needs only to compile: the public surface has to be shareable for the client to be usable at all
    func testPublicTypesAreSendable() {
        func requireSendable<T: Sendable>(_: T.Type) {}

        requireSendable(Ahoy.self)
        requireSendable(Configuration.self)
        requireSendable(Configuration.ApplicationEnvironment.self)
        requireSendable(Event.self)
        requireSendable(Visit.self)
        requireSendable(RequestInterceptor.self)
        requireSendable(AhoyError.self)
    }

    func testClientIsUsableAcrossIsolationDomains() async {
        let ahoy: Ahoy = .init(configuration: .testDefault)

        await Task.detached {
            ahoy.attach(userId: "12345")
            ahoy.track("from_detached_task", properties: ["source": "detached"])
        }.value

        await MainActor.run {
            ahoy.requestInterceptors = [
                .init { $0.addValue("intercepted", forHTTPHeaderField: "from-main-actor") }
            ]
        }

        XCTAssertEqual(ahoy.currentVisit?.userId, "12345")
        XCTAssertEqual(ahoy.requestInterceptors.count, 1)
        XCTAssertTrue(TestRequestHandler.instance.body.contains("from_detached_task"))
    }

    // MARK: - Helpers

    private func advancePastVisitDuration() {
        Current.date = { Date(timeIntervalSince1970: 0).advanced(by: Configuration.testDefault.visitDuration! + 1) }
    }

    private func postDidBecomeActive() {
        Current.notificationCenter.post(name: Current.didBecomeActiveNotification!, object: nil)
    }

    private func trackVisitAndWait(on ahoy: Ahoy, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = self.expectation(description: "visit")

        ahoy.trackVisit()
            .sink(
                receiveCompletion: { if case let .failure(error) = $0 { XCTFail("\(error)", file: file, line: line) } },
                receiveValue: { _ in expectation.fulfill() }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 0.1)
    }

    private func trackEventAndWait(on ahoy: Ahoy, named name: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = self.expectation(description: name)

        ahoy.track(events: [.init(name: name, properties: [:], time: .init(timeIntervalSince1970: 0))])
            .sink(
                receiveCompletion: { if case let .failure(error) = $0 { XCTFail("\(error)", file: file, line: line) } },
                receiveValue: { expectation.fulfill() }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 0.1)
    }

}

/// Completes visit requests immediately but holds event requests open, so a test can observe a
/// fire-and-forget subscription while it is genuinely in flight
final class DeferredEventsRequestHandler: @unchecked Sendable {
    nonisolated(unsafe) static let instance: DeferredEventsRequestHandler = .init()

    private typealias Output = Configuration.URLRequestPublisher.Output

    private let lock: NSLock = .init()
    private var pending: [(subject: PassthroughSubject<Output, URLError>, output: Output)] = []

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }

        return pending.count
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        pending = []
    }

    func publisher(for urlRequest: URLRequest) -> Configuration.URLRequestPublisher {
        let response = HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: "1.0", headerFields: [:])!
        let output: Output = (data: urlRequest.httpBody!, response: response)

        guard urlRequest.url!.lastPathComponent == "my-events" else {
            return Just(output).setFailureType(to: URLError.self).eraseToAnyPublisher()
        }

        let subject: PassthroughSubject<Output, URLError> = .init()

        lock.lock()
        pending.append((subject, output))
        lock.unlock()

        return subject.eraseToAnyPublisher()
    }

    func completePending() {
        lock.lock()
        let inFlight = pending
        pending = []
        lock.unlock()

        inFlight.forEach { subject, output in
            subject.send(output)
            subject.send(completion: .finished)
        }
    }
}

/// A minimal thread-safe box, so test doubles can be mutated from the `@Sendable` closures on `Current`
final class Locked<Value>: @unchecked Sendable {
    private let lock: NSLock = .init()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    var current: Value {
        lock.lock()
        defer { lock.unlock() }

        return value
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        body(&value)
    }
}

extension UUID {
    fileprivate static let firstToken: UUID = .init(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    fileprivate static let secondToken: UUID = .init(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!
}

extension Configuration {
    static let testDefault: Self = .init(
        environment: .testDefault,
        urlRequestHandler: { TestRequestHandler.instance.publisher(for: $0) },
        baseUrl: URL(string: "https://ahoy.com")!,
        ahoyPath: "test-ahoy",
        eventsPath: "my-events",
        visitsPath: "my-visits",
        visitDuration: .oneHour
    )

    static let manualTestDefault: Self = .init(
        environment: .testDefault,
        urlRequestHandler: { TestRequestHandler.instance.publisher(for: $0) },
        baseUrl: URL(string: "https://ahoy.com")!,
        ahoyPath: "test-ahoy",
        eventsPath: "my-events",
        visitsPath: "my-visits",
        visitDuration: .oneHour,
        automaticVisitRenewal: false
    )

    static let deferredEventsTestDefault: Self = .init(
        environment: .testDefault,
        urlRequestHandler: { DeferredEventsRequestHandler.instance.publisher(for: $0) },
        baseUrl: URL(string: "https://ahoy.com")!,
        ahoyPath: "test-ahoy",
        eventsPath: "my-events",
        visitsPath: "my-visits",
        visitDuration: .oneHour
    )

    static let visitParamsTestDefault: Self = .init(
        environment: .testDefault,
        urlRequestHandler: { TestRequestHandler.instance.publisher(for: $0) },
        baseUrl: URL(string: "https://ahoy.com")!,
        ahoyPath: "test-ahoy",
        eventsPath: "my-events",
        visitsPath: "my-visits",
        visitDuration: .oneHour,
        visitParams: { ["utm_source": "push"] }
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
    private(set) var requestCount = 0
    /// The body of the most recent request to the visits path
    private(set) var visitRequestBody: String!

    func reset() {
        headers = nil
        body = nil
        url = nil
        requestCount = 0
        visitRequestBody = nil
    }

    func publisher(for urlRequest: URLRequest) -> Configuration.URLRequestPublisher {
        headers = urlRequest.allHTTPHeaderFields
        body = String(data: urlRequest.httpBody!, encoding: .utf8)
        url = urlRequest.url
        requestCount += 1
        if url.lastPathComponent == "my-visits" {
            visitRequestBody = body
        }

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
    nonisolated(unsafe) static let instance: TestRequestHandler = .init()
}

final class TestDefaults: UserDefaults {
    nonisolated(unsafe) static let instance: TestDefaults = .init()

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
