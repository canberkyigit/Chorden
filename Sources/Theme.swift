import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark) : NSColor(hex: light)
        }
    }
}

enum Theme {
    static let windowBG = NSColor.dynamic(light: 0xF4F4F6, dark: 0x111214)

    static let bg = Color(nsColor: windowBG)
    static let surface = Color(nsColor: .dynamic(light: 0xFFFFFF, dark: 0x1A1B1F))
    static let line = Color(nsColor: .dynamic(light: 0xDCDCE2, dark: 0x2C2D33))
    static let faint = Color(nsColor: .dynamic(light: 0xC4C4CC, dark: 0x3A3B42))
    static let text = Color(nsColor: .labelColor)
    static let dim = Color(nsColor: .secondaryLabelColor)
    static let ghost = Color(nsColor: .tertiaryLabelColor)
    static let good = Color(nsColor: NSColor(hex: 0x34C77B))
    static let warn = Color(nsColor: NSColor(hex: 0xF0A33A))
    static let off = Color(nsColor: NSColor(hex: 0xE5484D))

    /// Needle / note color for a deviation: green inside tolerance, amber close, red far.
    static func tint(cents: Double, tolerance: Double, active: Bool) -> Color {
        guard active else { return ghost }
        let a = abs(cents)
        if a <= tolerance { return good }
        if a <= 15 { return warn }
        return off
    }
}

/// Quiet text button used for tabs and segmented choices: no chrome, just weight and color.
struct TextChoice: View {
    let title: String
    let selected: Bool
    var size: CGFloat = 12
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: size, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.text : Theme.dim)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(selected ? Theme.line.opacity(0.7) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Wrapping row layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // A zero/tiny proposal (min-size probing) shouldn't stack every chip into one column.
        let width = max(proposal.width ?? .infinity, 300)
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX {
                y += rowHeight + lineSpacing
                x = bounds.minX
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
