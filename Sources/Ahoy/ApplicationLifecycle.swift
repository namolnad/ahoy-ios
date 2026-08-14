import Foundation

#if canImport(WatchKit)
import WatchKit
#elseif canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ApplicationLifecycle {
    /// The platform's analogue of a web page load — the moment at which an expired visit should be renewed.
    /// `nil` on platforms which offer no such notification, in which case renewal happens lazily at event-tracking time.
    static var didBecomeActiveNotification: Notification.Name? {
        #if canImport(WatchKit)
        if #available(watchOS 7.0, *) {
            return WKExtension.applicationDidBecomeActiveNotification
        }
        return nil
        #elseif canImport(UIKit)
        return UIApplication.didBecomeActiveNotification
        #elseif canImport(AppKit)
        return NSApplication.didBecomeActiveNotification
        #else
        return nil
        #endif
    }

    /// Activations as an async sequence. Only the most recent is buffered: a burst of activations while one is
    /// being handled collapses to a single follow-up rather than a queue of redundant visit requests.
    static func activations(named name: Notification.Name) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let center = Current.notificationCenter

            nonisolated(unsafe) let token = center.addObserver(
                forName: name,
                object: nil,
                queue: nil
            ) { _ in
                continuation.yield(())
            }

            continuation.onTermination = { _ in
                center.removeObserver(token)
            }
        }
    }
}
