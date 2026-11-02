import SwiftUI
import ParlaCore

/// B: el panel de la lectura en vivo. Aparte del de las capturas, para que las
/// dos listas no se mezclen.
struct LivePanelView: View {
    let controller: LiveReadingController
    @Bindable var session: LiveSession

    private var rhythm: Binding<LiveRhythm> {
        Binding(get: { session.rhythm }, set: {
            session.rhythm = $0
            Preferences.shared.liveRhythm = $0
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("", selection: rhythm) {
                    Text("Automático").tag(LiveRhythm.automatic)
                    Text("Cuando yo diga").tag(LiveRhythm.onDemand)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button("Leer ahora") { Task { await session.readNow() } }
            }
            HStack(spacing: 6) {
                Image(systemName: "text.viewfinder").foregroundStyle(.secondary)
                Text(controller.sourceName).lineLimit(1)
                Text("·").foregroundStyle(.secondary)
                Image(systemName: "book.closed").foregroundStyle(.secondary)
                Text(controller.notebookName).lineLimit(1)
                Spacer()
                Button("Cambiar") { controller.reconfigure() }
                Button("Terminar") { controller.stop() }
            }
            .font(.caption)
            .buttonStyle(.link)

            if case .paused(let reason) = session.state {
                Label(reason.message, systemImage: "pause.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let notice = session.notice {
                Text(notice).font(.callout).foregroundStyle(.secondary)
            }

            Divider()
            if session.lines.isEmpty {
                Text(session.rhythm == .automatic
                     ? "Las líneas nuevas del recuadro aparecerán aquí."
                     : "Pulsa «Leer ahora» o ⌃⌥R cuando haya texto en el recuadro.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(session.lines) { line in
                            LiveLineRow(line: line,
                                        retry: { session.retry(line.id) },
                                        save: { session.save(line.id) },
                                        unsave: { session.unsave(line.id) })
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(minWidth: 380, minHeight: 260, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct LiveLineRow: View {
    let line: LiveLineState
    let retry: () -> Void
    let save: () -> Void
    let unsave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(line.english)
                .font(.system(.callout, design: .serif))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            switch line.status {
            case .translating:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Traduciendo…").foregroundStyle(.secondary)
                }
            case .translated(let translation):
                Text(translation.spanish).textSelection(.enabled)
                ForEach(translation.expressions, id: \.phrase) { expression in
                    Text("\(Text(expression.phrase).bold()): \(expression.meaning)")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    if line.isSaved {
                        Button { unsave() } label: {
                            Label("Guardada", systemImage: "bookmark.fill")
                        }
                        .help("Quitar del cuaderno")
                    } else {
                        Button { save() } label: { Label("Guardar", systemImage: "bookmark") }
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            case .untranslated(let reason):
                HStack {
                    Text("sin traducir").italic().foregroundStyle(.secondary)
                    Text("· \(reason)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reintentar", action: retry).buttonStyle(.borderless).font(.caption)
                }
            }
        }
    }
}
