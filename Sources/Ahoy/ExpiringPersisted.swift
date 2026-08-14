import Foundation

@propertyWrapper
struct ExpiringPersisted<T: Codable> {
    let key: String
    let newValue: () -> T
    private(set) var expiryPeriod: TimeInterval? = nil
    let jsonEncoder: JSONEncoder
    let jsonDecoder: JSONDecoder

    /// Guards the read-check-mint-write below so that concurrent readers can't mint competing values,
    /// which would otherwise scatter a single session's events across several visits
    private let lock: NSLock = .init()

    /// Returns the stored value, minting — and persisting — a replacement when nothing is stored or the stored value has expired.
    var wrappedValue: T {
        lock.lock()
        defer { lock.unlock() }

        guard let container = storedContainer, !container.hasExpired(after: expiryPeriod) else {
            let container: DatedStorageContainer = .init(
                storageDate: Current.date(),
                value: newValue()
            )
            if let data = try? jsonEncoder.encode(container) {
                defaults.set(data, forKey: key)
            }

            return container.value
        }
        return container.value
    }

    /// Whether an unexpired value is currently stored. Reading `wrappedValue` while this is `false` mints a new value.
    var projectedValue: Bool {
        lock.lock()
        defer { lock.unlock() }

        return storedContainer.map { !$0.hasExpired(after: expiryPeriod) } ?? false
    }

    /// Resolved on access rather than captured at initialization so that `Current` can be substituted in tests.
    private var defaults: UserDefaults {
        Current.defaults
    }

    private var storedContainer: DatedStorageContainer<T>? {
        guard let data = defaults.value(forKey: key) as? Data else { return nil }

        return try? jsonDecoder.decode(DatedStorageContainer<T>.self, from: data)
    }

    private struct DatedStorageContainer<Value: Codable>: Codable {
        let storageDate: Date
        let value: Value

        /// A `nil` period never expires
        func hasExpired(after period: TimeInterval?) -> Bool {
            guard let period = period else { return false }

            return storageDate.advanced(by: period) <= Current.date()
        }
    }
}
