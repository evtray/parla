import Foundation

/// Decide cuándo el texto de un recuadro es una línea nueva.
///
/// Un diálogo de juego aparece letra por letra y Vision lee cada fotograma con
/// pequeñas diferencias. Una línea sale cuando dos lecturas seguidas coinciden
/// (el texto se asentó) y no se parece a la última que salió (una letra mal
/// leída no la repite). Un recuadro vacío olvida la última, para que una frase
/// que vuelve a salir tras cerrarse el cuadro cuente otra vez.
public struct LineDetector: Sendable {
    public static let similarityThreshold = 0.9

    private var candidate: String?
    private var lastEmitted: String?

    public init() {}

    /// La línea, cuando el texto se asentó y no es la última que se soltó.
    public mutating func feed(_ text: String) -> String? {
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else {
            candidate = nil
            lastEmitted = nil
            return nil
        }
        if normalized == candidate,
           Self.similarity(normalized, lastEmitted ?? "") < Self.similarityThreshold {
            lastEmitted = normalized
            return normalized
        }
        candidate = normalized
        return nil
    }

    /// Leer ahora: suelta el texto aunque se repita. `nil` solo si está vacío.
    public mutating func force(_ text: String) -> String? {
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else { return nil }
        candidate = normalized
        lastEmitted = normalized
        return normalized
    }

    /// Los bordes del cuadro de diálogo se leen a veces como `|`, `_` o `—`:
    /// fuera de los extremos, y los espacios repetidos, uno solo.
    public static func normalize(_ text: String) -> String {
        let edges = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "|_~•·—–-=[]{}<>"))
        return text.trimmingCharacters(in: edges)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// 1 − distancia de Levenshtein / longitud de la más larga; 0 si alguna está vacía.
    public static func similarity(_ a: String, _ b: String) -> Double {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1,
                                 previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return 1 - Double(previous[b.count]) / Double(max(a.count, b.count))
    }
}
