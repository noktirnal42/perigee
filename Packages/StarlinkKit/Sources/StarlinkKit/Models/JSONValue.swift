import Foundation

/// Tiny read-only accessor over a decoded protobuf-JSON document.
/// The device protos are huge and mostly irrelevant; the mapping layer only pulls the fields the UI shows,
/// and this keeps that code compact, tolerant of absent (default) fields, and fixture-testable.
public struct JSONValue: @unchecked Sendable {
    let raw: Any?
    init(_ raw: Any?) { self.raw = raw }

    public init(data: Data) {
        self.raw = try? JSONSerialization.jsonObject(with: data)
    }

    public subscript(_ key: String) -> JSONValue {
        guard let dict = raw as? [String: Any] else { return JSONValue(nil) }
        return JSONValue(dict[key])
    }

    public subscript(path: [String]) -> JSONValue { path.reduce(self) { $0[$1] } }

    public var exists: Bool { raw != nil }
    public var array: [JSONValue] { (raw as? [Any])?.map { JSONValue($0) } ?? [] }
    public var keys: [String] { (raw as? [String: Any]).map { Array($0.keys).sorted() } ?? [] }

    public var string: String? {
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return n.stringValue }
        return nil
    }

    public var double: Double? {
        if let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue.isFinite ? n.doubleValue : nil }
        if let s = raw as? String { // protobuf-JSON encodes int64 as strings and NaN as "NaN"
            guard let d = Double(s), d.isFinite else { return nil }
            return d
        }
        return nil
    }

    public var int: Int? { double.flatMap { Int(exactly: $0.rounded()) } }
    public var bool: Bool? { (raw as? NSNumber).map { $0.boolValue } ?? (raw as? Bool) }
}
