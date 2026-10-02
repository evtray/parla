import SwiftUI
import KeyboardShortcuts
import ParlaCore

struct WelcomeView: View {
    @Bindable var state: AppState
    let onFinish: () -> Void
    @State private var flow = WelcomeFlow()
    @State private var keyEntry = APIKeyEntry()
    /// Return dispara el campo y el botón por defecto a la vez: una sola
    /// comprobación.
    @State private var isSubmitting = false

    private var setup: SetupMonitor { state.setup }

    private var hasSavedKey: Bool {
        !setup.status.issues.contains { $0.item == .apiKey }
    }

    private func issue(_ item: SetupItem) -> SetupIssue? {
        setup.status.issues.first { $0.item == item }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ProgressDots(current: flow.step.rawValue, total: WelcomeStep.allCases.count)
                .frame(maxWidth: .infinity)
            Group {
                switch flow.step {
                case .hello: hello
                case .key: key
                case .permissions: permissions
                case .ready: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(24)
        .frame(width: 480, height: 440)
        .task { await setup.refresh() }
    }

    private var hello: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bienvenida a Parla").font(.title.weight(.semibold))
            Text("Tres formas de practicar inglés sin dejar lo que estás haciendo:")
                .foregroundStyle(.secondary)
            ModeLine(symbol: "mic", title: "Voz",
                     text: "Dices una frase en español y te la da en inglés, con el porqué.")
            ModeLine(symbol: "crop", title: "Captura",
                     text: "Seleccionas texto en pantalla y te lo explica, corrige o traduce.")
            ModeLine(symbol: "captions.bubble", title: "Subtítulos",
                     text: "Traduce al momento lo que suena en tu Mac, como un video.")
        }
    }

    private var key: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tu clave de Anthropic").font(.title2.weight(.semibold))
            Text("La voz y las capturas usan Claude. La clave se guarda en el Llavero de tu Mac "
                 + "y solo viaja a Anthropic.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if hasSavedKey {
                Label("Ya hay una clave guardada. Pega otra solo si quieres cambiarla.",
                      systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
            SecureField("sk-ant-…", text: $keyEntry.text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submitKey)
            if keyEntry.isChecking {
                ProgressView("Comprobando la clave…").controlSize(.small)
            }
            if let message = flow.keyMessage {
                Text(message).font(.callout).foregroundStyle(.orange)
            }
            Link("Consigue una clave en la consola de Anthropic",
                 destination: URL(string: "https://console.anthropic.com/settings/keys")!)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permisos").font(.title2.weight(.semibold))
            if let message = flow.keyMessage {
                Text(message).font(.callout).foregroundStyle(.orange)
            }
            PermissionLine(symbol: "mic", title: "Micrófono", reason: "Para el modo voz.",
                           issue: issue(.microphone), setup: setup)
            PermissionLine(symbol: "rectangle.dashed", title: "Grabación de pantalla",
                           reason: "Para las capturas y los subtítulos.",
                           issue: issue(.screenRecording), setup: setup)
            Text("macOS te preguntará al pulsar «Permitir». Puedes cambiarlo cuando quieras en "
                 + "Ajustes del Sistema › Privacidad.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Listo").font(.title2.weight(.semibold))
            if let languages = issue(.languages) {
                SetupIssueRow(issue: languages, setup: setup) {}
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Atajos").font(.headline)
                ForEach(ParlaMode.allCases, id: \.self) { mode in
                    ShortcutLine(mode: mode)
                }
            }
            MenuBarHint()
        }
    }

    private var footer: some View {
        HStack {
            if !flow.isLast {
                Button("Ahora no") { flow.advance() }
            }
            Spacer()
            if flow.isLast {
                Button("Empezar", action: onFinish)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continuar", action: continueTapped)
                    .keyboardShortcut(.defaultAction)
                    .disabled(keyEntry.isChecking)
            }
        }
    }

    private func continueTapped() {
        if flow.step == .key { submitKey() } else { flow.advance() }
    }

    private func submitKey() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            let check = await keyEntry.submit()
            setup.refreshNow()
            flow.keySubmitted(check, hasSavedKey: hasSavedKey)
            isSubmitting = false
        }
    }
}

private struct ProgressDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Theme.accent : Color.secondary.opacity(0.3))
                    .frame(width: 22, height: 4)
            }
        }
        .accessibilityLabel("Paso \(current + 1) de \(total)")
    }
}

private struct ModeLine: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(text).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PermissionLine: View {
    let symbol: String
    let title: String
    let reason: String
    let issue: SetupIssue?
    let setup: SetupMonitor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let issue {
                VStack(alignment: .trailing, spacing: 4) {
                    if let label = issue.fix.buttonTitle {
                        Button(label) { Task { await setup.perform(issue.fix) } }
                    }
                    if issue.fix == .openScreenRecordingSettingsOrRelaunch {
                        Button("Reabrir Parla") { setup.relaunch() }
                    }
                }
                .controlSize(.small)
            } else {
                Label("Listo", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ShortcutLine: View {
    let mode: ParlaMode

    var body: some View {
        let model = ModeTileModel(
            mode: mode, isActive: false,
            shortcut: KeyboardShortcuts.getShortcut(for: mode.shortcutName)?.description)
        HStack {
            Label(model.title, systemImage: model.symbol)
            Spacer()
            Text(model.caption).foregroundStyle(.secondary).monospaced()
        }
        .font(.callout)
    }
}

/// macOS no ofrece una forma pública de abrir ni de localizar el icono de otra
/// app en la barra de menús: se enseña con un dibujo.
private struct MenuBarHint: View {
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "wifi")
                Image(systemName: "character.bubble")
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.accent, lineWidth: 1.5))
                Text("12:30")
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            Text("Parla vive aquí, en la barra de menús, arriba a la derecha.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
