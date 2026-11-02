import Foundation
import ImageIO
import ParlaCore

/// Sonda 1 de la lectura en vivo: ¿lee Vision bien los cuadros de diálogo?
/// Compara cada `.png` con su `.txt`, normalizados igual que el detector.
func evalOCR(in path: String) async throws {
    let folder = URL(fileURLWithPath: path)
    let images = try FileManager.default
        .contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension.lowercased() == "png" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var exact = 0
    for file in images {
        let name = file.lastPathComponent
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            print("✗ \(name): no se pudo abrir")
            continue
        }
        let expected = (try? String(contentsOf: file.deletingPathExtension().appendingPathExtension("txt"),
                                    encoding: .utf8)) ?? ""
        let start = ContinuousClock.now
        let text = try await TextReader.read(image)
        let elapsed = ContinuousClock.now - start
        let milliseconds = elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000
        let ok = LineDetector.normalize(text) == LineDetector.normalize(expected)
        if ok { exact += 1 }
        print("\(ok ? "✓" : "✗") \(name) (\(milliseconds) ms)")
        print("   leído:    \(text)")
        if !ok { print("   esperado: \(LineDetector.normalize(expected))") }
    }
    print("\n\(exact)/\(images.count) exactas")
}
