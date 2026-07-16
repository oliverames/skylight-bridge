import CoreGraphics
import Foundation

enum ReminderListColor {
    static func normalizedHex(_ rawValue: String?) -> String? {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let value = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard value.count == 6,
              value.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return "#\(value.uppercased())"
    }

    static func hex(for color: CGColor?) -> String? {
        guard let color,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let sRGB = color.converted(
                  to: colorSpace,
                  intent: .defaultIntent,
                  options: nil
              ),
              let components = sRGB.components,
              components.count >= 3 else {
            return nil
        }

        let red = UInt8((components[0].clamped(to: 0...1) * 255).rounded())
        let green = UInt8((components[1].clamped(to: 0...1) * 255).rounded())
        let blue = UInt8((components[2].clamped(to: 0...1) * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    static func cgColor(for rawValue: String) -> CGColor? {
        guard let hex = normalizedHex(rawValue) else { return nil }
        let value = String(hex.dropFirst())
        guard let red = UInt8(value.prefix(2), radix: 16),
              let green = UInt8(value.dropFirst(2).prefix(2), radix: 16),
              let blue = UInt8(value.suffix(2), radix: 16),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        return CGColor(
            colorSpace: colorSpace,
            components: [
                CGFloat(red) / 255,
                CGFloat(green) / 255,
                CGFloat(blue) / 255,
                1
            ]
        )
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
