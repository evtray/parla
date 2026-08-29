import SwiftUI

struct PanelView: View {
    @Bindable var state: AppState

    /// La cola se enseña también con la escucha apagada: apagar no manda nada,
    /// así que el botón de traducir tiene que seguir a la vista.
    private var showsQueue: Bool {
        state.mode == .batch
            && (!state.pending.isEmpty || state.isSendingBatch || state.batchError != nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let progress = state.downloadProgress {
                    ProgressView("Descargando modelo de español…", value: progress)
                        .font(.caption)
                }

                if !state.partialText.isEmpty {
                    Text(state.partialText)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }

                if state.needsMicrophoneAccess {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Parla necesita acceso al micrófono.").font(.callout)
                        Button("Abrir Ajustes del Sistema") {
                            AppState.openMicrophoneSettings()
                        }
                        .controlSize(.small)
                    }
                }

                if let warning = state.silentInputWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = state.setupError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }

                if showsQueue {
                    QueueView(utterances: state.pendingPreview,
                              total: state.pending.count,
                              isSending: state.isSendingBatch,
                              error: state.batchError,
                              onSend: { state.sendBatch() },
                              onDiscard: { state.discardPending() })
                }

                if !state.batchSummary.isEmpty {
                    SummaryView(lines: state.batchSummary)
                }

                ForEach(state.visibleCards) { card in
                    CardView(presentation: card) { state.retry(card) }
                }

                if !state.isListening && !state.visibleCards.isEmpty {
                    Button("Cerrar el panel") { state.hidePanel() }
                        .buttonStyle(.link)
                        .font(.caption)
                        .padding(.top, 2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.easeOut(duration: 0.18), value: state.visibleCards.count)
        .animation(.easeOut(duration: 0.18), value: state.pending.count)
    }
}
