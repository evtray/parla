import Testing
import CoreGraphics
import ParlaCore
@testable import Parla

private func blankImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
}

@Test func elRecorteSeCalculaSobreElTamañoDelFotograma() throws {
    let setup = LiveSetup(source: .window(bundleID: "com.afk", title: "AFK"),
                          region: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5), notebookID: nil)
    let cropped = try #require(RegionWatcher.crop(blankImage(width: 400, height: 300), setup: setup))
    #expect(cropped.width == 200)
    #expect(cropped.height == 150)
}

@Test func conLaPantallaElFotogramaYaVieneRecortado() throws {
    let setup = LiveSetup(source: .screen, region: CGRect(x: 10, y: 10, width: 300, height: 80),
                          notebookID: nil)
    let cropped = try #require(RegionWatcher.crop(blankImage(width: 600, height: 160), setup: setup))
    #expect(cropped.width == 600)
}
