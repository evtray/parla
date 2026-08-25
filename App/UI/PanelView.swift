import SwiftUI

struct PanelView: View {
    @Bindable var state: AppState

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

                if let error = state.setupError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }

                ForEach(state.visibleCards) { card in
                    CardView(presentation: card) { state.retry(card) }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.easeOut(duration: 0.18), value: state.visibleCards.count)
    }
}
