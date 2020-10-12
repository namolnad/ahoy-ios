#if !os(watchOS)
import XCTest
#endif

#if !canImport(ObjectiveC)
@available(iOS 13, tvOS 13, macOS 10.15, *)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(AhoyTests.allTests),
    ]
}
#endif
