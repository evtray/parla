import CoreGraphics
import Foundation
import Vision

/// Lee el texto de un recuadro con Vision, en el propio equipo: la imagen no
/// sale de la Mac (ni del iPhone, que también tiene Vision).
public enum TextReader {
    public static let minimumConfidence: Float = 0.3

    /// Las líneas de arriba abajo, unidas con un espacio. "" si no hay texto.
    public static func read(_ image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: image)
        let lines: [(box: CGRect, text: String)] = observations
            .filter { $0.confidence >= minimumConfidence }
            .compactMap { observation in
                guard let text = observation.topCandidates(1).first?.string, !text.isEmpty
                else { return nil }
                return (observation.boundingBox.cgRect, text)
            }
        // Vision mide desde abajo: la línea de más arriba tiene el maxY mayor.
        let sorted = lines.sorted { a, b in
            a.box.maxY != b.box.maxY ? a.box.maxY > b.box.maxY : a.box.minX < b.box.minX
        }
        return sorted.map(\.text).joined(separator: " ")
    }
}
