// GLPIKiosk — JSONConversions.swift
// Helpers de conversion Any? -> type Swift issus du JSON.
// Partagés entre services et vues (remplace les copies privées en double).

import Foundation

func asString(_ value: Any?) -> String? {
    if let v = value as? String { return v }
    if let v = value as? Int    { return String(v) }
    if let v = value as? Double { return String(v) }
    if let v = value as? Bool   { return v ? "true" : "false" }
    return nil
}

func asInt(_ value: Any?) -> Int? {
    if let v = value as? Int    { return v }
    if let v = value as? Double { return Int(v) }
    if let v = value as? String { return Int(v) }
    return nil
}

func asDouble(_ value: Any?) -> Double? {
    if let v = value as? Double { return v }
    if let v = value as? Int    { return Double(v) }
    if let v = value as? String { return Double(v) }
    return nil
}
