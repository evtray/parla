import SwiftData
import SwiftUI
import ParlaCore

/// ⌃⌥L la primera vez: de dónde leer, qué recuadro y en qué cuaderno.
struct LiveSetupFlow: View {
    let controller: LiveReadingController
    @State var flow: LiveSetupFlowModel
    let windows: [WindowCandidate]

    @Query(sort: \Notebook.createdAt, order: .reverse) private var notebooks: [Notebook]
    @State private var isPicking = false
    @State private var failedPick = false
    @State private var newName = ""
    @State private var newAbout = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch flow.nextStep {
            case .source?: sourceStep
            case .region?: regionStep
            case .notebook?: notebookStep
            case nil: ProgressView()
            }
        }
        .padding(20)
        .frame(width: 460, height: 420, alignment: .topLeading)
        .onChange(of: flow.nextStep) { _, step in
            if step == nil, let setup = flow.setup { controller.start(setup) }
        }
    }

    // MARK: - Pasos

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("¿De dónde leo?").font(.title3.weight(.semibold))
            Text("Elige la ventana del juego o del material. Parla la sigue aunque la muevas.")
                .font(.callout).foregroundStyle(.secondary)
            List {
                ForEach(windows, id: \.windowID) { window in
                    Button { flow.choose(window: window) } label: {
                        VStack(alignment: .leading) {
                            Text(LiveReadingController.appName(for: window.bundleID))
                            if !window.title.isEmpty {
                                Text(window.title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button { flow.chooseScreen() } label: {
                    Label("Un recuadro de la pantalla", systemImage: "rectangle.dashed")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var regionStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Marca el recuadro").font(.title3.weight(.semibold))
            Text("Arrastra sobre la zona donde aparece el texto, por ejemplo el cuadro de "
                 + "diálogo. Parla solo lee lo que quede dentro.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if failedPick {
                Text("No quedó marcado ningún recuadro dentro de la ventana. Prueba otra vez.")
                    .font(.callout).foregroundStyle(.red)
            }
            Button("Marcar el recuadro") { pick() }
                .keyboardShortcut(.defaultAction)
                .disabled(isPicking)
        }
    }

    private var notebookStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("¿En qué cuaderno?").font(.title3.weight(.semibold))
            Text("El cuaderno le da contexto a la traducción y guarda las líneas que valen la pena.")
                .font(.callout).foregroundStyle(.secondary)
            List {
                ForEach(notebooks) { notebook in
                    Button(notebook.name) { flow.chooseNotebook(notebook.id) }
                        .buttonStyle(.plain)
                }
                Button("Sin cuaderno") { flow.chooseNotebook(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 140)
            GroupBox("Nuevo cuaderno") {
                VStack(alignment: .leading) {
                    TextField("Nombre", text: $newName)
                    TextField("De qué trata", text: $newAbout,
                              prompt: Text("Ej.: RPG de fantasía; Maren es la capitana…"),
                              axis: .vertical)
                        .lineLimit(2...3)
                    Button("Crear y empezar") { create() }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Acciones

    private func pick() {
        guard let source = flow.source else { return }
        isPicking = true
        Task {
            defer { isPicking = false }
            if let region = await controller.pickRegion(for: source, windows: windows) {
                failedPick = false
                flow.chooseRegion(region)
            } else {
                failedPick = true
            }
        }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let about = newAbout.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let id = await controller.notebooks.createNotebook(name: name, about: about)
            flow.chooseNotebook(id)
        }
    }
}
