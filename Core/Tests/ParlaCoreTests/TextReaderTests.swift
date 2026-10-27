import Testing
import CoreGraphics
import CoreText
import Foundation
@testable import ParlaCore

/// Texto negro de 32 pt sobre blanco, una línea debajo de otra.
private func render(_ lines: [String]) -> CGImage {
    let width = 900, height = 200
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = CTFontCreateWithName("Helvetica" as CFString, 32, nil)
    for (index, line) in lines.enumerated() {
        let attributed = NSAttributedString(string: line, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        ])
        // CoreGraphics mide desde abajo: la primera línea va más arriba.
        context.textPosition = CGPoint(x: 30, y: CGFloat(height - 70 - index * 60))
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
    }
    return context.makeImage()!
}

@Test func leeLasLineasDeArribaAbajoEnUnSoloTexto() async throws {
    let text = try await TextReader.read(render(["The Gloomwood stirs again.",
                                                 "We have to hold the line."]))
    #expect(text == "The Gloomwood stirs again. We have to hold the line.")
}

@Test func unaImagenSinTextoDevuelveVacio() async throws {
    #expect(try await TextReader.read(render([])) == "")
}
