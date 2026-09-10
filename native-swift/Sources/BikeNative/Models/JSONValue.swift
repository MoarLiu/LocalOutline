import Foundation

// Preserve fields introduced by other clients without interpreting them.
enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Decimal)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let item = try? value.decode(Bool.self) { self = .bool(item) }
        else if let item = try? value.decode(String.self) { self = .string(item) }
        else if let item = try? value.decode(Decimal.self) { self = .number(item) }
        else if let item = try? value.decode([JSONValue].self) { self = .array(item) }
        else { self = .object(try value.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let item): try value.encode(item)
        case .number(let item): try value.encode(item)
        case .string(let item): try value.encode(item)
        case .array(let item): try value.encode(item)
        case .object(let item): try value.encode(item)
        }
    }
}

private struct JSONFieldKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

extension Decoder {
    func additionalFields<Key: CodingKey & CaseIterable>(excluding: Key.Type) throws -> [String: JSONValue] {
        let known = Set(Key.allCases.map(\.stringValue))
        let container = try container(keyedBy: JSONFieldKey.self)
        var fields: [String: JSONValue] = [:]
        for key in container.allKeys where !known.contains(key.stringValue) {
            fields[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        return fields
    }
}

extension Encoder {
    func encodeAdditionalFields<Key: CodingKey & CaseIterable>(_ fields: [String: JSONValue], excluding: Key.Type) throws {
        let known = Set(Key.allCases.map(\.stringValue))
        var container = container(keyedBy: JSONFieldKey.self)
        for (key, value) in fields where !known.contains(key) {
            try container.encode(value, forKey: JSONFieldKey(stringValue: key))
        }
    }
}
