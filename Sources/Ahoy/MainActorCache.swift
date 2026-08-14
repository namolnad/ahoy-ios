import Foundation

/// Holds a value whose platform only exposes it on the main actor, so that code running elsewhere can still
/// use it once it has been read.
///
/// `resolve()` reads through when it is called from the main actor and caches the result; from anywhere else it
/// returns what has already been cached, or `nil` if nothing has. Callers are expected to resolve once at a
/// point they control — see `Ahoy.init` — rather than relying on the read-through.
final class MainActorCache<Value: Sendable>: @unchecked Sendable {
    private let lock: NSLock = .init()
    private var cached: Value?
    private let read: @MainActor () -> Value?

    init(read: @escaping @MainActor () -> Value?) {
        self.read = read
    }

    func resolve() -> Value? {
        if let cached = currentValue { return cached }

        // `assumeIsolated` would trap off the main actor, and there is nothing to hop to it from here:
        // this is called beneath a lock, so suspending or blocking on the main queue risks deadlock.
        guard Thread.isMainThread else { return nil }

        let resolved = MainActor.assumeIsolated { read() }
        store(resolved)

        return resolved
    }

    private var currentValue: Value? {
        lock.lock()
        defer { lock.unlock() }

        return cached
    }

    private func store(_ value: Value?) {
        lock.lock()
        defer { lock.unlock() }

        cached = value
    }
}
