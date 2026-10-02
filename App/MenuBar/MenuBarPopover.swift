import SwiftUI
import SwiftData
import KeyboardShortcuts
import ParlaCore

struct MenuBarPopover: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Query(MenuBarPopover.lastCard) private var last: [StoredCard]

    static var lastCard: FetchDescriptor<StoredCard> {
        var descriptor = FetchDescriptor<StoredCard>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    private var notices: NoticeList {
        NoticeList(runtime: state.runtimeNotices,
                   issues: state.setup.status.issues,
                   priority: state.blockedMode.map { state.setup.status.startBlockers(for: $0) } ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ModeTile(model: tile(.voice)) { toggle(.voice) }
                ModeTile(model: tile(.capture)) { capture() }
                ModeTile(model: tile(.subtitles)) { toggle(.subtitles) }
            }

            if !notices.visible.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(notices.visible) { notice in
                        switch notice {
                        case .setup(let issue):
                            SetupIssueRow(issue: issue, setup: state.setup) { open(.settings) }
                        case .runtime(let runtime):
                            RuntimeNoticeRow(notice: runtime) { state.dismiss(runtime) }
                        }
                    }
                    if notices.hiddenCount > 0 {
                        Button(notices.hiddenCount == 1 ? "y 1 más" : "y \(notices.hiddenCount) más") {
                            open(nil)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if state.mode == .batch, !state.pending.isEmpty {
                Button(state.pending.count == 1
                       ? "Traducir 1 frase"
                       : "Traducir \(state.pending.count) frases") {
                    state.sendBatch()
                }
                .disabled(state.isSendingBatch)
                .frame(maxWidth: .infinity)
            }

            if let card = last.first {
                Divider()
                LastPhraseView(card: card) { open(.history) }
            }

            Divider()
            HStack {
                Button("Abrir Estudio") { open(nil) }
                Spacer()
                Button { open(.settings) } label: { Image(systemName: "gearshape") }
                    .help("Ajustes")
                Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Salir de Parla")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 300)
        .task { await state.setup.refresh() }
        .background {
            Button("Ajustes") { open(.settings) }
                .keyboardShortcut(",", modifiers: .command)
                .hidden()
        }
    }

    private func tile(_ mode: ParlaMode) -> ModeTileModel {
        let isActive = switch mode {
        case .voice: state.isListening
        case .subtitles: state.isSubtitling
        case .capture: false
        }
        return ModeTileModel(mode: mode, isActive: isActive,
                             shortcut: KeyboardShortcuts.getShortcut(for: mode.shortcutName)?.description)
    }

    /// Apagar siempre se puede. Encender con algo pendiente no arranca: los
    /// avisos ya están a la vista y lo que lo impide sube arriba.
    private func toggle(_ mode: ParlaMode) {
        let isOn = mode == .voice ? state.isListening : state.isSubtitling
        guard isOn || !state.isBlocked(mode) else { return }
        if mode == .voice {
            state.toggleListening()
        } else {
            state.toggleSubtitles()
        }
    }

    /// La cruz no debe tener el menú emergente delante.
    private func capture() {
        guard !state.isBlocked(.capture) else { return }
        dismiss()
        state.captureScreen()
    }

    private func open(_ section: StudioSection?) {
        dismiss()
        state.windows.showStudio(section)
    }
}
