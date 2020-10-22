import Foundation

public struct Event: Encodable {
    enum CodingKeys: CodingKey {
        case id
        case name
        case properties
        case time
    }

    let id: String?
    let name: String
    let properties: [String: Encodable]
    let time: Date

    public init(
        id: String? = nil,
        name: String,
        properties: [String : Encodable],
        time: Date = .init()
    ) {
        self.id = id
        self.name = name
        self.properties = properties
        self.time = time
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(properties, forKey: .properties)
        try container.encode(time, forKey: .time)
    }
}
