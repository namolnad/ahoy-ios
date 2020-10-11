import Foundation

struct Environment {
    var date: () -> Date = Date.init
    var uuid: () -> UUID = UUID.init
    var visitorToken: () -> UUID = visitorTokenProvider
    var defaults: UserDefaults = .standard
}

#if DEBUG
var Current: Environment = .init()
#else
let Current: Environment = .init()
#endif

#if canImport(WatchKit)
import WatchKit

let visitorTokenProvider: () -> UUID = {
    WKInterfaceDevice.current().identifierForVendor ?? Current.uuid()
}
#elseif canImport(UIKit)
import UIKit

let visitorTokenProvider: () -> UUID = {
    UIDevice.current.identifierForVendor ?? Current.uuid()
}
#elseif canImport(AppKit)
import AppKit

let visitorTokenProvider: () -> UUID = {
    let matchingDict = IOServiceMatching("IOPlatformExpertDevice")
    let platformExpert = IOServiceGetMatchingService(kIOMasterPortDefault, matchingDict)

    defer { IOObjectRelease(platformExpert) }

    guard
        platformExpert != 0,
        let uuidString = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault, 0
        ).takeRetainedValue() as? String,
        let uuid = UUID(uuidString: uuidString)
    else { return Current.uuid() }

    return uuid
}
#endif
