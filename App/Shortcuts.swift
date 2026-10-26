import KeyboardShortcuts
import ParlaCore

extension KeyboardShortcuts.Name {
    static let toggleListening = Self("toggleListening",
                                      default: .init(.space, modifiers: [.control, .option]))
    static let captureScreen = Self("captureScreen",
                                    initial: .init(.c, modifiers: [.control, .option]))
    static let toggleSubtitles = Self("toggleSubtitles",
                                      initial: .init(.s, modifiers: [.control, .option]))
}

extension ParlaMode {
    /// El atajo global de cada modo, para enseñarlo donde se ofrece el modo.
    var shortcutName: KeyboardShortcuts.Name {
        switch self {
        case .voice: .toggleListening
        case .capture: .captureScreen
        case .subtitles: .toggleSubtitles
        }
    }
}
