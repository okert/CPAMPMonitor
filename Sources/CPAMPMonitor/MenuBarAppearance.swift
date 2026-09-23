import AppKit

struct MenuBarAppearance: Codable, Equatable {
    enum Border: String, Codable, CaseIterable {
        case none, square, circle

        var title: String {
            switch self {
            case .none: return "无"
            case .square: return "方形"
            case .circle: return "圆形"
            }
        }
    }

    var showIcon = true
    var showPercent = true
    var border: Border = .none

    func badge(_ text: String) -> NSImage {
        let size: CGFloat = 20
        let inset: CGFloat = border == .circle ? 4 : 2
        var font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        while (text as NSString).size(withAttributes: [.font: font]).width > size - inset * 2,
              font.pointSize > 5 {
            font = .monospacedDigitSystemFont(ofSize: font.pointSize - 0.5, weight: .medium)
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.black.setStroke()
            let bounds = rect.insetBy(dx: 0.75, dy: 0.75)
            let path = self.border == .circle
                ? NSBezierPath(ovalIn: bounds)
                : NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2)
            path.lineWidth = 1
            path.stroke()
            (text as NSString).draw(at: NSPoint(x: (size - textSize.width) / 2,
                                               y: (size - textSize.height) / 2), withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        return image
    }
}
