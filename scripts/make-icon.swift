#!/usr/bin/env swift
// Dibuja el icono de Parla: «Aa» en serif, crema sobre terracota.
//
// Uso:
//   swift scripts/make-icon.swift appiconset <carpeta .appiconset>   # a sangre completa
//   swift scripts/make-icon.swift rounded <carpeta .appiconset>      # forma clásica, con margen
//   swift scripts/make-icon.swift glyph <archivo .png>               # solo «Aa», para Icon Composer
import AppKit

let terracota = NSColor(srgbRed: 0xD8 / 255, green: 0x5A / 255, blue: 0x30 / 255, alpha: 1)
let crema = NSColor(srgbRed: 0xFA / 255, green: 0xEC / 255, blue: 0xE7 / 255, alpha: 1)

enum Style { case fullBleed, rounded, glyph }

func render(pixels: Int, style: Style) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let side = CGFloat(pixels)
    switch style {
    case .fullBleed:
        terracota.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
    case .rounded:
        // La rejilla clásica de macOS: 824 de 1024, radio 185.
        let body = side * 824 / 1024
        let inset = (side - body) / 2
        terracota.setFill()
        NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: body, height: body),
                     xRadius: side * 185 / 1024, yRadius: side * 185 / 1024).fill()
    case .glyph:
        break
    }
    let size = side * (style == .rounded ? 0.38 : 0.46)
    let base = NSFont.systemFont(ofSize: size, weight: .medium)
    let font = base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    let text = NSAttributedString(string: "Aa", attributes: [.font: font, .foregroundColor: crema])
    let bounds = text.size()
    text.draw(at: NSPoint(x: (side - bounds.width) / 2, y: (side - bounds.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("uso: make-icon.swift appiconset|rounded|glyph <destino>")
    exit(2)
}
let destination = URL(fileURLWithPath: arguments[2])

if arguments[1] == "glyph" {
    try render(pixels: 1024, style: .glyph).write(to: destination)
    exit(0)
}

let style: Style = arguments[1] == "rounded" ? .rounded : .fullBleed
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    try render(pixels: pixels, style: style)
        .write(to: destination.appending(path: "icon_\(pixels).png"))
}
// Cada tamaño en puntos, a 1x y a 2x.
let slots: [(points: Int, scale: Int)] = [16, 32, 128, 256, 512].flatMap { [($0, 1), ($0, 2)] }
let images = slots.map { slot in
    """
        { "filename" : "icon_\(slot.points * slot.scale).png", "idiom" : "mac", \
    "scale" : "\(slot.scale)x", "size" : "\(slot.points)x\(slot.points)" }
    """
}
let contents = """
{
  "images" : [
\(images.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try contents.write(to: destination.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
