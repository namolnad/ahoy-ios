import Foundation

@propertyWrapper
struct ExpiringPersisted<T: Codable> {
    let key: String
    let newValue: () -> T
    var expiryPeriod: TimeInterval? = nil
    var defaults: UserDefaults = Current.defaults
    var jsonEncoder: JSONEncoder
    var jsonDecoder: JSONDecoder

    var wrappedValue: T {
        guard
            let data = defaults.value(forKey: key) as? Data,
            case let container = try! jsonDecoder.decode(ExpiringContainer<T>.self, from: data),
            !container.expired
        else {
            let container: ExpiringContainer = .init(
                expiry: expiryPeriod.map(Current.date().addingTimeInterval),
                value: newValue()
            )
            defaults.set(try! jsonEncoder.encode(container), forKey: key)

            return container.value
        }
        return container.value
    }

    private struct ExpiringContainer<T: Codable>: Codable {
        let expiry: Date?
        let value: T

        var expired: Bool {
            guard let expiry = expiry else {
                return false
            }
            return Current.date() > expiry
        }
    }
}
