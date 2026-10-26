import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Deja la captura en lo que el modelo aprovecha. Lo que pase de ahí, la API lo
/// reduce igual: mandarlo es pagar bytes y latencia por nada.
///
/// Límites de los modelos de alta resolución (Opus 5.5, Sonnet 5.5), según la
/// documentación de visión a 2026-10-01.
enum ImageDownscaler {
    static let maxLongEdge = 2576
    static let maxVisualTokens = 4784
    static let maxBase64Bytes = 10_000_000

    enum Failure: Error, Equatable {
        case unreadable
        /// Ni reducida ni en JPEG cabe en el límite de la API.
        case tooLarge
    }

    struct Prepared: Equatable {
        let data: Data
        let mediaType: String
    }

    /// El modelo ve la imagen en parches de 28×28 píxeles.
    static func visualTokens(width: Int, height: Int) -> Int {
        ((width + 27) / 28) * ((height + 27) / 28)
    }

    /// El tamaño más grande que cabe en los dos límites conservando la
    /// proporción. Nunca amplía.
    static func fittedSize(width: Int, height: Int) -> (width: Int, height: Int) {
        func scaled(_ scale: Double) -> (width: Int, height: Int) {
            (max(1, Int(Double(width) * scale)), max(1, Int(Double(height) * scale)))
        }
        var scale = min(1.0, Double(maxLongEdge) / Double(max(width, height)))
        while true {
            let size = scaled(scale)
            if visualTokens(width: size.width, height: size.height) <= maxVisualTokens {
                return size
            }
            scale *= 0.99
        }
    }

    static func base64Size(_ data: Data) -> Int { (data.count + 2) / 3 * 4 }

    /// PNG siempre que quepa: el texto se lee mejor sin artefactos de
    /// compresión. JPEG solo si el PNG no cabe (un fotograma de vídeo con
    /// subtítulos puede no caber).
    static func prepare(_ imageData: Data,
                        maxBase64Bytes: Int = maxBase64Bytes) throws -> Prepared {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Failure.unreadable }

        let target = fittedSize(width: image.width, height: image.height)
        let unchanged = target.width == image.width && target.height == image.height
        let isPNG = (CGImageSourceGetType(source) as String?) == UTType.png.identifier
        let scaled = unchanged ? image : try resize(image, to: target)

        let png = unchanged && isPNG ? imageData : try encode(scaled, as: .png)
        if base64Size(png) <= maxBase64Bytes {
            return Prepared(data: png, mediaType: "image/png")
        }
        let jpeg = try encode(scaled, as: .jpeg, quality: 0.9)
        if base64Size(jpeg) <= maxBase64Bytes {
            return Prepared(data: jpeg, mediaType: "image/jpeg")
        }
        throw Failure.tooLarge
    }

    static func encode(_ image: CGImage, as type: UTType, quality: Double? = nil) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, type.identifier as CFString, 1, nil)
        else { throw Failure.unreadable }
        let options = quality.map {
            [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary
        }
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable }
        return data as Data
    }

    private static func resize(_ image: CGImage,
                               to size: (width: Int, height: Int)) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: size.width, height: size.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Failure.unreadable }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let resized = context.makeImage() else { throw Failure.unreadable }
        return resized
    }
}
