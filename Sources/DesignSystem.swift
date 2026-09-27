import AppKit
import SwiftUI

/// The visual language: paper, two inks, three faces.
///
/// The app is a notebook. Colour means *when*, not *what* — short-term tasks are
/// written in fresh iron-gall navy, long-term ones in aged sepia. Sections are
/// told apart by their four-letter code, not by a colour of their own.
enum Paper {
    /// A colour that follows the system appearance without a SwiftUI asset catalogue.
    private static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green:   CGFloat((value >> 8) & 0xFF) / 255,
                blue:    CGFloat(value & 0xFF) / 255,
                alpha: 1)
    }

    /// The page itself.
    static let sheet   = dynamic(hex(0xF4F5F2), hex(0x17181A))
    /// Slightly lifted areas — the header and footer bands.
    static let band    = dynamic(hex(0xFAFAF8), hex(0x1D1F21))
    static let ink     = dynamic(hex(0x1A1C1B), hex(0xECEDE9))
    static let muted   = dynamic(hex(0x7C8079), hex(0x8B8F88))
    static let faint   = dynamic(hex(0xA9ADA4), hex(0x6A6E68))
    /// The row under the pointer.
    static let hover   = dynamic(hex(0xE9EAE5), hex(0x232527))
    /// Hairlines: the margin, the section rules, the field underlines.
    static let rule    = dynamic(hex(0xDFE0DB), hex(0x303234))

    /// Fresh ink — the short-term view.
    static let fresh   = dynamic(hex(0x1D3557), hex(0x8AAEDC))
    /// Aged ink — the long-term view.
    static let aged    = dynamic(hex(0x7C4A32), hex(0xCC9270))
    /// The marginal mark on a starred task.
    static let mark    = dynamic(hex(0xB08423), hex(0xD8A94A))

    /// A task past its due date.
    static let overdue = dynamic(hex(0xC0392B), hex(0xF0716A))

    static func accent(for horizon: Horizon) -> Color {
        horizon == .shortTerm ? fresh : aged
    }
}

/// Three faces, each with one job.
enum Face {
    /// New York, for the wordmark only.
    static let wordmark = Font.system(size: 21, weight: .semibold, design: .serif)
    /// SF Mono, for codes, counts and shortcuts.
    static func code(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// SF Pro, for the tasks themselves — the only text that is arbitrary.
    static func task(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 13, weight: weight)
    }
}

extension Bucket {
    /// Four letters each, so the codes set a true column in a monospaced face.
    var code: String {
        switch self {
        case .readings:    return "READ"
        case .assignments: return "ASGN"
        case .emails:      return "MAIL"
        case .other:       return "MISC"
        }
    }
}
