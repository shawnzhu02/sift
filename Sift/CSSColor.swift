import SwiftUI

/// Parses the CSS colors pages report (`rgb()`, `rgba()`, `#rgb`, `#rrggbb`, `#rrggbbaa`).
enum CSSColor {
    struct RGBA: Equatable {
        var r: Double, g: Double, b: Double, a: Double
    }

    static func parse(_ text: String) -> RGBA? {
        let s = text.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("#") { return hex(String(s.dropFirst())) }
        guard let open = s.firstIndex(of: "("), s.hasSuffix(")"),
              s.hasPrefix("rgb") else { return nil }
        let inner = s[s.index(after: open)..<s.index(before: s.endIndex)]
        // Accept both "r, g, b, a" and "r g b / a".
        let parts = inner
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .split(separator: " ")
            .map(String.init)
        guard parts.count == 3 || parts.count == 4 else { return nil }
        func channel(_ p: String) -> Double? {
            if p.hasSuffix("%"), let v = Double(p.dropLast()) { return max(0, min(1, v / 100)) }
            return Double(p).map { max(0, min(1, $0 / 255)) }
        }
        func alpha(_ p: String) -> Double? {
            if p.hasSuffix("%"), let v = Double(p.dropLast()) { return max(0, min(1, v / 100)) }
            return Double(p).map { max(0, min(1, $0)) }
        }
        guard let r = channel(parts[0]), let g = channel(parts[1]), let b = channel(parts[2]) else { return nil }
        let a = parts.count == 4 ? alpha(parts[3]) : 1
        guard let a else { return nil }
        return RGBA(r: r, g: g, b: b, a: a)
    }

    private static func hex(_ h: String) -> RGBA? {
        var digits = h
        if digits.count == 3 || digits.count == 4 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard digits.count == 6 || digits.count == 8, let v = UInt64(digits, radix: 16) else { return nil }
        if digits.count == 6 {
            return RGBA(r: Double((v >> 16) & 0xff) / 255, g: Double((v >> 8) & 0xff) / 255, b: Double(v & 0xff) / 255, a: 1)
        }
        return RGBA(r: Double((v >> 24) & 0xff) / 255, g: Double((v >> 16) & 0xff) / 255,
                    b: Double((v >> 8) & 0xff) / 255, a: Double(v & 0xff) / 255)
    }

    /// An opaque SwiftUI color, or nil for unparseable or see-through values.
    static func color(_ text: String) -> Color? {
        guard let c = parse(text), c.a > 0.5 else { return nil }
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}
