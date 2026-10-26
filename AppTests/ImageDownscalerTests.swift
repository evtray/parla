import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Parla

/// Una imagen de prueba: un rectángulo negro sobre blanco, o ruido, que no
/// comprime y sirve para forzar tamaños grandes.
private func image(width: Int, height: Int, noise: Bool = false, type: UTType = .png) -> Data {
    let context = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if noise {
        let count = context.bytesPerRow * height
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: count)
        for index in 0 ..< count { pixels[index] = UInt8.random(in: 0 ... 255) }
    } else {
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: max(1, height / 8)))
    }
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

private func pixelSize(of data: Data) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    return (image.width, image.height)
}

@Test func losTokensSonParchesDe28() {
    #expect(ImageDownscaler.visualTokens(width: 1000, height: 1000) == 1296)
    #expect(ImageDownscaler.visualTokens(width: 2576, height: 1449) == 4784)
}

@Test func unaImagenGrandeCabeEnAmbosLimites() {
    let size = ImageDownscaler.fittedSize(width: 4000, height: 3000)
    #expect(max(size.width, size.height) <= 2576)
    let tokens = ImageDownscaler.visualTokens(width: size.width, height: size.height)
    #expect(tokens <= 4784)
    // Que quepa no basta: tampoco puede encogerse de más y perder legibilidad.
    #expect(tokens > 4500)
    #expect(abs(Double(size.width) / Double(size.height) - 4.0 / 3.0) < 0.01)
}

@Test func nuncaAmplia() {
    let size = ImageDownscaler.fittedSize(width: 100, height: 50)
    #expect(size.width == 100 && size.height == 50)
}

@Test func unPNGPequenoPasaSinTocar() throws {
    let original = image(width: 800, height: 200)
    let prepared = try ImageDownscaler.prepare(original)
    #expect(prepared.data == original)
    #expect(prepared.mediaType == "image/png")
}

@Test func unaRegionDiminutaPasaIntacta() throws {
    // Un clic sin arrastrar puede dejar una región de unos pocos píxeles.
    let original = image(width: 4, height: 4)
    let prepared = try ImageDownscaler.prepare(original)
    #expect(prepared.data == original)
}

@Test func reduceDeVerdadLaImagen() throws {
    let prepared = try ImageDownscaler.prepare(image(width: 4000, height: 3000))
    let size = try #require(pixelSize(of: prepared.data))
    let expected = ImageDownscaler.fittedSize(width: 4000, height: 3000)
    #expect(size.width == expected.width && size.height == expected.height)
    #expect(prepared.mediaType == "image/png")
}

@Test func unJPEGSeConvierteAPNG() throws {
    let prepared = try ImageDownscaler.prepare(image(width: 300, height: 100, type: .jpeg))
    #expect(prepared.mediaType == "image/png")
    #expect(pixelSize(of: prepared.data)?.width == 300)
}

@Test func siElPNGNoCabeSeRecodificaComoJPEG() throws {
    // El ruido no comprime en PNG; en JPEG sí. El límite se pone entre los dos
    // tamaños medidos, no adivinados.
    let original = image(width: 600, height: 600, noise: true)
    let source = try #require(CGImageSourceCreateWithData(original as CFData, nil))
    let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let jpegSize = ImageDownscaler.base64Size(
        try ImageDownscaler.encode(decoded, as: .jpeg, quality: 0.9))
    let pngSize = ImageDownscaler.base64Size(original)
    try #require(jpegSize < pngSize)
    let limit = (jpegSize + pngSize) / 2
    let prepared = try ImageDownscaler.prepare(original, maxBase64Bytes: limit)
    #expect(prepared.mediaType == "image/jpeg")
    #expect(ImageDownscaler.base64Size(prepared.data) <= limit)
}

@Test func siNiElJPEGCabeFalla() {
    #expect(throws: ImageDownscaler.Failure.tooLarge) {
        try ImageDownscaler.prepare(image(width: 100, height: 100), maxBase64Bytes: 10)
    }
}

@Test func unosBytesQueNoSonImagenFallan() {
    #expect(throws: ImageDownscaler.Failure.unreadable) {
        try ImageDownscaler.prepare(Data("hola".utf8))
    }
}
