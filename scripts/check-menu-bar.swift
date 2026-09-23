import AppKit

// Run with swiftc Sources/CPAMPMonitor/MenuBarAppearance.swift scripts/check-menu-bar.swift -o /tmp/check-menu-bar
@main struct MenuBarChecks {
    static func main() throws {
        let defaults = MenuBarAppearance()
        precondition(defaults.showIcon && defaults.showPercent && defaults.border == .none)
        for border in MenuBarAppearance.Border.allCases {
            for icon in [false, true] {
                for percent in [false, true] {
                    let appearance = MenuBarAppearance(showIcon: icon, showPercent: percent, border: border)
                    let data = try JSONEncoder().encode(appearance)
                    let restored = try JSONDecoder().decode(MenuBarAppearance.self, from: data)
                    precondition(restored == appearance)
                }
            }
        }
        let sheet = NSImage(size: NSSize(width: 240, height: 80))
        sheet.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 240, height: 80).fill()
        for (row, border) in [MenuBarAppearance.Border.square, .circle].enumerated() {
            for (column, text) in ["0", "9", "42", "100", "100%", "--"].enumerated() {
                let badge = MenuBarAppearance(border: border).badge(text)
                precondition(badge.isTemplate && badge.size == NSSize(width: 20, height: 20))
                precondition(badge.tiffRepresentation != nil)
                badge.draw(in: NSRect(x: column * 40 + 10, y: row * 40 + 10, width: 20, height: 20))
            }
        }
        sheet.unlockFocus()
        let bitmap = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/cpamp-menu-bar-check.png"))
        print("PASS Menu bar defaults, 12 persistence combinations and 12 badge renders")
    }
}
