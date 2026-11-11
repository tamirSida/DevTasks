// Renders Resources/AppIcon.icns. Run: swift scripts/make_icon.swift
import AppKit
import CoreText

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let fontURL = root.appendingPathComponent("Resources/fa-solid-900.ttf")
CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bg = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(starting: NSColor(red: 0.09, green: 0.11, blue: 0.15, alpha: 1),
               ending: NSColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1))!.draw(in: bg, angle: -90)
    NSColor(red: 0.37, green: 0.95, blue: 0.65, alpha: 0.25).setStroke()
    bg.lineWidth = s * 0.006
    bg.stroke()

    let mint = NSColor(red: 0.37, green: 0.95, blue: 0.65, alpha: 1)
    // checkbox
    let box = NSRect(x: rect.minX + rect.width * 0.17, y: rect.midY - rect.width * 0.17,
                     width: rect.width * 0.34, height: rect.width * 0.34)
    let boxPath = NSBezierPath(roundedRect: box, xRadius: box.width * 0.26, yRadius: box.width * 0.26)
    mint.setFill(); boxPath.fill()
    let fa = NSFont(name: "FontAwesome6Free-Solid", size: box.width * 0.6)!
    let check = NSAttributedString(string: "\u{f00c}", attributes: [.font: fa, .foregroundColor: NSColor(red: 0.02, green: 0.08, blue: 0.05, alpha: 1)])
    let cs = check.size()
    check.draw(at: NSPoint(x: box.midX - cs.width / 2, y: box.midY - cs.height / 2))
    // cursor
    let cursor = NSRect(x: box.maxX + rect.width * 0.08, y: box.minY, width: rect.width * 0.2, height: rect.width * 0.065)
    mint.setFill(); NSBezierPath(roundedRect: cursor, xRadius: cursor.height * 0.3, yRadius: cursor.height * 0.3).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
