import Foundation
#if !os(watchOS)
import XCTest
#endif
@testable import Ahoy

#if !os(watchOS)
final class AhoyTests: XCTestCase {
    private var ahoy: Ahoy!

    private let configuration: Configuration = .testDefault

    override func setUp() {
        super.setUp()

        Current = .init()
        TestDefaults.instance.reset()
        TestRequestHandler.instance.reset()
        DeferredVisitsRequestHandler.instance.reset()
        Current.defaults = TestDefaults.instance
        Current.date = { .init(timeIntervalSince1970: 0) }
        Current.visitorToken = { UUID(uuidString: "EB4DCB73-2B32-52CD-A2CF-AD7948674B22")! }
        Current.didBecomeActiveNotification = .init("ahoy_test_did_become_active")
        Current.notificationCenter = .init()

        ahoy = .init(configuration: configuration)
    }

    func testTrackVisit() async throws {
        let visitDuration = configuration.visitDuration!

        let actual1 = await ahoy.currentVisit
        XCTAssertNil(actual1)

        Current.uuid = { .firstToken }

        var testHeaders: [String: String] = [
            "Ahoy-Visit": UUID.firstToken.uuidString,
            "Ahoy-Visitor": "EB4DCB73-2B32-52CD-A2CF-AD7948674B22",
            "Content-Type": " application/json; charset=utf-8"
        ]

        try await ahoy.trackVisit()

        XCTAssertEqual(TestRequestHandler.instance.headers, testHeaders)
        XCTAssertEqual(
            TestRequestHandler.instance.body,
            "{\"app_version\":\"9.9.99\",\"os_version\":\"16.0.2\",\"platform\":\"iOS\",\"visit_token\":\"\(UUID.firstToken.uuidString)\",\"visitor_token\":\"EB4DCB73-2B32-52CD-A2CF-AD7948674B22\"}"
        )
        XCTAssertEqual(TestRequestHandler.instance.url.absoluteString, "https://ahoy.com/test-ahoy/my-visits")
        let actual2 = await ahoy.headers["Ahoy-Visitor"]
        XCTAssertEqual(actual2, "EB4DCB73-2B32-52CD-A2CF-AD7948674B22")

        // Still inside the visit window: the same token is re-registered
        Current.date = { Date(timeIntervalSince1970: 0).advanced(by: visitDuration - 1) }
        Current.uuid = { .secondToken }

        try await ahoy.trackVisit(additionalParams: ["utm_source": "some-place", "source": 3])

        XCTAssertEqual(
            TestRequestHandler.instance.body,
            "{\"app_version\":\"9.9.99\",\"os_version\":\"16.0.2\",\"platform\":\"iOS\",\"source\":3,\"utm_source\":\"some-place\",\"visit_token\":\"\(UUID.firstToken.uuidString)\",\"visitor_token\":\"EB4DCB73-2B32-52CD-A2CF-AD7948674B22\"}"
        )
        XCTAssertEqual(TestRequestHandler.instance.headers, testHeaders)
        let actual3 = await ahoy.currentVisit?.visitToken
        XCTAssertEqual(actual3, UUID.firstToken.uuidString)

        // Past the window: a new token is minted
        Current.date = { Date(timeIntervalSince1970: 0).advanced(by: visitDuration + 10) }
        await ahoy.setRequestInterceptors([
            .init { $0.addValue("intercepted", forHTTPHeaderField: "intercept-test") }
        ])

        testHeaders["Ahoy-Visit"] = UUID.secondToken.uuidString
        testHeaders["intercept-test"] = "intercepted"

        try await ahoy.trackVisit()

        XCTAssertEqual(TestRequestHandler.instance.headers, testHeaders)
        let actual4 = await ahoy.currentVisit?.visitToken
        XCTAssertEqual(actual4, UUID.secondToken.uuidString)
        let actual5 = await ahoy.headers["Ahoy-Visit"]
        XCTAssertEqual(actual5, UUID.secondToken.uuidString)
    }

    func testTrackEvents() async throws {
        Current.uuid = { UUID(uuidString: "98C44594-050F-4DEF-80AF-AB723472469B")! }

        try await ahoy.trackVisit()
        try await ahoy.track(events: [
            .init(name: "test", properties: ["123": 456], time: .init(timeIntervalSince1970: 0))
        ])

        XCTAssertEqual(
            TestRequestHandler.instance.body,
            "{\"events\":[{\"name\":\"test\",\"properties\":{\"123\":456},\"time\":\"1970-01-01T00:00:00Z\"}],\"visit_token\":\"98C44594-050F-4DEF-80AF-AB723472469B\",\"visitor_token\":\"EB4DCB73-2B32-52CD-A2CF-AD7948674B22\"}"
        )
    }

    func testTrackEventsWithAttachedUser() async throws {
        Current.uuid = { UUID(uuidString: "98C44594-050F-4DEF-80AF-AB723472469B")! }

        try await ahoy.trackVisit()
        await ahoy.attach(userId: "12345")
        try await ahoy.track(events: [
            .init(name: "test", properties: ["123": 456], time: .init(timeIntervalSince1970: 0))
        ])

        XCTAssertEqual(
            TestRequestHandler.instance.body,
            "{\"events\":[{\"name\":\"test\",\"properties\":{\"123\":456},\"time\":\"1970-01-01T00:00:00Z\",\"user_id\":\"12345\"}],\"visit_token\":\"98C44594-050F-4DEF-80AF-AB723472469B\",\"visitor_token\":\"EB4DCB73-2B32-52CD-A2CF-AD7948674B22\"}"
        )
    }

    // MARK: - Automatic visit renewal

    /// The heart of https://github.com/namolnad/ahoy-ios/issues/4: events tracked after the visit has lapsed must
    /// land on a fresh visit rather than the stale one captured at launch — as ahoy.js does on the web.
    func testEventTrackingRenewsExpiredVisit() async throws {
        Current.uuid = { .firstToken }

        try await ahoy.trackVisit()

        let actual6 = await ahoy.currentVisit?.visitToken
        XCTAssertEqual(actual6, UUID.firstToken.uuidString)

        advancePastVisitDuration()
        Current.uuid = { .secondToken }

        try await track(named: "after_expiry", on: ahoy)

        let actual7 = await ahoy.currentVisit?.visitToken
        XCTAssertEqual(actual7, UUID.secondToken.uuidString)
        XCTAssertEqual(TestRequestHandler.instance.headers["Ahoy-Visit"], UUID.secondToken.uuidString)
        XCTAssertTrue(TestRequestHandler.instance.body.contains("\"visit_token\":\"\(UUID.secondToken.uuidString)\""))
        XCTAssertTrue(TestRequestHandler.instance.body.contains("after_expiry"))
    }

    func testEventTrackingReusesUnexpiredVisit() async throws {
        Current.uuid = { .firstToken }

        try await ahoy.trackVisit()

        let requestsAfterVisit = TestRequestHandler.instance.requestCount

        let visitDuration = configuration.visitDuration!
        Current.date = { Date(timeIntervalSince1970: 0).advanced(by: visitDuration - 1) }
        Current.uuid = { .secondToken }

        try await track(named: "within_duration", on: ahoy)

        let actual8 = await ahoy.currentVisit?.visitToken
        XCTAssertEqual(actual8, UUID.firstToken.uuidString)
        // Only the events request — no visit was registered
        XCTAssertEqual(TestRequestHandler.instance.requestCount, requestsAfterVisit + 1)
    }

    /// A visit no longer needs to be tracked by hand before events can be sent
    func testEventTrackingCreatesInitialVisit() async throws {
        Current.uuid = { .firstToken }

        let actual9 = await ahoy.currentVisit
        XCTAssertNil(actual9)

        try await track(named: "no_prior_visit", on: ahoy)

        let actual10 = await ahoy.currentVisit?.visitToken
        XCTAssertEqual(actual10, UUID.firstToken.uuidString)
        XCTAssertTrue(TestRequestHandler.instance.body.contains("no_prior_visit"))
    }

    func testBecomingActiveRenewsExpiredVisit() async throws {
        Current.uuid = { .firstToken }

        try await ahoy.trackVisit()

        advancePastVisitDuration()
        Current.uuid = { .secondToken }

        postDidBecomeActive()

        await waitUntil("the visit to be renewed") { [ahoy] in
            await ahoy?.currentVisit?.visitToken == UUID.secondToken.uuidString
        }
    }

    func testBecomingActiveLeavesUnexpiredVisitAlone() async throws {
        Current.uuid = { .firstToken }

        try await ahoy.trackVisit()

        let requestsAfterVisit = TestRequestHandler.instance.requestCount
        Current.uuid = { .secondToken }

        postDidBecomeActive()
        await settle()

        let actual11 = await ahoy.currentVisit?.visitToken
        XCTAssertEqual(actual11, UUID.firstToken.uuidString)
        XCTAssertEqual(TestRequestHandler.instance.requestCount, requestsAfterVisit)
    }

    func testRenewedVisitUsesConfiguredVisitParams() async throws {
        Current.uuid = { .firstToken }

        let ahoy: Ahoy = .init(configuration: .visitParamsTestDefault)

        try await track(named: "renewed", on: ahoy)

        XCTAssertEqual(
            TestRequestHandler.instance.visitRequestBody,
            "{\"app_version\":\"9.9.99\",\"os_version\":\"16.0.2\",\"platform\":\"iOS\",\"utm_source\":\"push\",\"visit_token\":\"\(UUID.firstToken.uuidString)\",\"visitor_token\":\"EB4DCB73-2B32-52CD-A2CF-AD7948674B22\"}"
        )
    }

    func testAttachedUserSurvivesVisitRenewal() async throws {
        Current.uuid = { .firstToken }

        try await ahoy.trackVisit()
        await ahoy.attach(userId: "12345")

        advancePastVisitDuration()
        Current.uuid = { .secondToken }

        try await track(named: "after_expiry", on: ahoy)

        let actual12 = await ahoy.currentVisit?.visitToken
        XCTAssertEqual(actual12, UUID.secondToken.uuidString)
        let actual13 = await ahoy.currentVisit?.userId
        XCTAssertEqual(actual13, "12345")
        XCTAssertTrue(TestRequestHandler.instance.body.contains("\"user_id\":\"12345\""))
    }

    func testDetachUserClearsAttachment() async throws {
        Current.uuid = { .firstToken }

        try await ahoy.trackVisit()
        await ahoy.attach(userId: "12345")
        await ahoy.detachUser()

        advancePastVisitDuration()
        Current.uuid = { .secondToken }

        try await track(named: "after_expiry", on: ahoy)

        let actual14 = await ahoy.currentVisit?.userId
        XCTAssertNil(actual14)
        XCTAssertFalse(TestRequestHandler.instance.body.contains("user_id"))
    }

    /// Callers arriving while a visit request is in flight must share it. Each would otherwise register
    /// its own visit and scatter the batch across several of them.
    func testConcurrentTrackingRegistersASingleVisit() async throws {
        Current.uuid = { .firstToken }

        let handler = DeferredVisitsRequestHandler.instance
        let ahoy: Ahoy = .init(configuration: .deferredVisitsTestDefault)

        let epoch: Date = .init(timeIntervalSince1970: 0)

        async let first: Void = ahoy.track(events: [.init(name: "first", properties: [:], time: epoch)])
        async let second: Void = ahoy.track(events: [.init(name: "second", properties: [:], time: epoch)])
        async let third: Void = ahoy.track(events: [.init(name: "third", properties: [:], time: epoch)])

        await waitUntil("the visit request to be in flight") { handler.suspendedVisitCount >= 1 }
        // Let the other two callers reach `ensureCurrentVisit` and find the pending request
        await settle()

        handler.resumeSuspendedVisits()

        _ = try await (first, second, third)

        XCTAssertEqual(handler.visitRequestCount, 1, "The three callers shared one visit request")
        XCTAssertEqual(handler.eventRequestCount, 3)
    }

    // MARK: - Manual visit management

    func testManualRenewalFailsWithoutAVisit() async {
        let manual: Ahoy = .init(configuration: .manualTestDefault)

        do {
            try await manual.track(events: [.init(name: "test", properties: [:], time: .init(timeIntervalSince1970: 0))])
            XCTFail("Expected AhoyError.noVisit")
        } catch AhoyError.noVisit {
            // expected
        } catch {
            XCTFail("Expected AhoyError.noVisit, got \(error)")
        }
    }

    func testManualRenewalKeepsExpiredVisit() async throws {
        Current.uuid = { .firstToken }

        let manual: Ahoy = .init(configuration: .manualTestDefault)

        try await manual.trackVisit()

        advancePastVisitDuration()
        Current.uuid = { .secondToken }

        postDidBecomeActive()
        await settle()
        try await track(named: "after_expiry", on: manual)

        let actual15 = await manual.currentVisit?.visitToken
        XCTAssertEqual(actual15, UUID.firstToken.uuidString)
    }

    // MARK: - Fire-and-forget tracking

    /// Nothing is retained on the client's behalf, so this only has to arrive
    func testFireAndForgetTrackingDelivers() async {
        Current.uuid = { .firstToken }

        ahoy.track("fire_and_forget", properties: ["count": 1])

        await waitUntil("the event to be delivered") {
            TestRequestHandler.instance.body?.contains("fire_and_forget") == true
        }
    }

    func testFireAndForgetTrackingIsCallableFromASynchronousContext() {
        Current.uuid = { .firstToken }

        // Compiles without `await` or a surrounding Task, which is the point of the nonisolated overload
        ahoy.track("from_sync_context")
    }

    // MARK: - Visit stream

    func testVisitsStreamReplaysCurrentAndYieldsRenewals() async throws {
        Current.uuid = { .firstToken }

        try await ahoy.trackVisit()

        var iterator = ahoy.visits.makeAsyncIterator()

        let replayed = await iterator.next()
        XCTAssertEqual(replayed?.visitToken, UUID.firstToken.uuidString, "The current visit is replayed on subscribe")

        advancePastVisitDuration()
        Current.uuid = { .secondToken }

        try await ahoy.trackVisit()

        let renewed = await iterator.next()
        XCTAssertEqual(renewed?.visitToken, UUID.secondToken.uuidString)
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

    func testClientIsUsableAcrossIsolationDomains() async throws {
        Current.uuid = { .firstToken }

        let ahoy: Ahoy = .init(configuration: .testDefault)

        try await Task.detached {
            await ahoy.attach(userId: "12345")
            try await ahoy.track(events: [
                .init(name: "from_detached_task", properties: [:], time: .init(timeIntervalSince1970: 0))
            ])
        }.value

        await MainActor.run {
            ahoy.track("from_main_actor")
        }

        let actual16 = await ahoy.currentVisit?.userId
        XCTAssertEqual(actual16, "12345")
    }

    // MARK: - Helpers

    private func advancePastVisitDuration() {
        Current.date = { Date(timeIntervalSince1970: 0).advanced(by: Configuration.testDefault.visitDuration! + 1) }
    }

    private func postDidBecomeActive() {
        Current.notificationCenter.post(name: Current.didBecomeActiveNotification!, object: nil)
    }

    private func track(named name: String, on ahoy: Ahoy) async throws {
        try await ahoy.track(events: [.init(name: name, properties: [:], time: .init(timeIntervalSince1970: 0))])
    }

    /// Lets already-scheduled work run without introducing a wall-clock sleep
    private func settle(iterations: Int = 200) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }

    private func waitUntil(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () async -> Bool
    ) async {
        for _ in 0..<10_000 {
            if await condition() { return }
            await Task.yield()
        }

        XCTFail("Timed out waiting for \(description)", file: file, line: line)
    }

}

extension Configuration {
    static let testDefault: Self = .init(
        environment: .testDefault,
        urlRequestHandler: { try await TestRequestHandler.instance.handle($0) },
        baseUrl: URL(string: "https://ahoy.com")!,
        ahoyPath: "test-ahoy",
        eventsPath: "my-events",
        visitsPath: "my-visits",
        visitDuration: .oneHour
    )

    static let manualTestDefault: Self = .init(
        environment: .testDefault,
        urlRequestHandler: { try await TestRequestHandler.instance.handle($0) },
        baseUrl: URL(string: "https://ahoy.com")!,
        ahoyPath: "test-ahoy",
        eventsPath: "my-events",
        visitsPath: "my-visits",
        visitDuration: .oneHour,
        automaticVisitRenewal: false
    )

    static let deferredVisitsTestDefault: Self = .init(
        environment: .testDefault,
        urlRequestHandler: { try await DeferredVisitsRequestHandler.instance.handle($0) },
        baseUrl: URL(string: "https://ahoy.com")!,
        ahoyPath: "test-ahoy",
        eventsPath: "my-events",
        visitsPath: "my-visits",
        visitDuration: .oneHour
    )

    static let visitParamsTestDefault: Self = .init(
        environment: .testDefault,
        urlRequestHandler: { try await TestRequestHandler.instance.handle($0) },
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

final class TestRequestHandler: @unchecked Sendable {
    nonisolated(unsafe) static let instance: TestRequestHandler = .init()

    private let lock: NSLock = .init()
    private var _headers: [String: String]!
    private var _body: String!
    private var _url: URL!
    private var _requestCount = 0
    private var _visitRequestBody: String!

    var headers: [String: String]! { lock.withLockedValue { _headers } }
    var body: String! { lock.withLockedValue { _body } }
    var url: URL! { lock.withLockedValue { _url } }
    var requestCount: Int { lock.withLockedValue { _requestCount } }
    /// The body of the most recent request to the visits path
    var visitRequestBody: String! { lock.withLockedValue { _visitRequestBody } }

    func reset() {
        lock.withLockedValue {
            _headers = nil
            _body = nil
            _url = nil
            _requestCount = 0
            _visitRequestBody = nil
        }
    }

    func handle(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let body = String(data: request.httpBody!, encoding: .utf8)

        lock.withLockedValue {
            _headers = request.allHTTPHeaderFields
            _body = body
            _url = request.url
            _requestCount += 1
            if request.url!.lastPathComponent == "my-visits" {
                _visitRequestBody = body
            }
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "1.0",
            headerFields: request.allHTTPHeaderFields
        )!

        return (request.httpBody!, response)
    }
}

/// Holds visit requests open so a test can observe several callers arriving while one is in flight.
/// Event requests complete immediately.
final class DeferredVisitsRequestHandler: @unchecked Sendable {
    nonisolated(unsafe) static let instance: DeferredVisitsRequestHandler = .init()

    private let lock: NSLock = .init()
    private var _suspended: [CheckedContinuation<Void, Never>] = []
    private var _visitRequestCount = 0
    private var _eventRequestCount = 0

    var suspendedVisitCount: Int { lock.withLockedValue { _suspended.count } }
    var visitRequestCount: Int { lock.withLockedValue { _visitRequestCount } }
    var eventRequestCount: Int { lock.withLockedValue { _eventRequestCount } }

    func reset() {
        lock.withLockedValue {
            _suspended = []
            _visitRequestCount = 0
            _eventRequestCount = 0
        }
    }

    func handle(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let isVisit = request.url!.lastPathComponent == "my-visits"

        lock.withLockedValue {
            if isVisit {
                _visitRequestCount += 1
            } else {
                _eventRequestCount += 1
            }
        }

        if isVisit {
            await withCheckedContinuation { continuation in
                lock.withLockedValue { _suspended.append(continuation) }
            }
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "1.0",
            headerFields: request.allHTTPHeaderFields
        )!

        return (request.httpBody!, response)
    }

    func resumeSuspendedVisits() {
        let suspended: [CheckedContinuation<Void, Never>] = lock.withLockedValue {
            let pending = _suspended
            _suspended = []
            return pending
        }

        suspended.forEach { $0.resume() }
    }
}

final class TestDefaults: UserDefaults, @unchecked Sendable {
    nonisolated(unsafe) static let instance: TestDefaults = .init()

    private let storageLock: NSLock = .init()
    private var storage: [String: Any] = [:]

    override func set(_ value: Any?, forKey key: String) {
        storageLock.withLockedValue { storage[key] = value }
    }

    override func value(forKey key: String) -> Any? {
        storageLock.withLockedValue { storage[key] }
    }

    func reset() {
        storageLock.withLockedValue { storage = [:] }
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
        lock.withLockedValue { value }
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.withLockedValue { body(&value) }
    }
}

extension NSLock {
    func withLockedValue<R>(_ body: () -> R) -> R {
        lock()
        defer { unlock() }

        return body()
    }
}

extension UUID {
    fileprivate static let firstToken: UUID = .init(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    fileprivate static let secondToken: UUID = .init(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!
}
#endif
