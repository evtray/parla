import SwiftData
import SwiftUI

enum NotebookListEntry: Hashable {
    case notebook(UUID)
    /// Las líneas leídas sin cuaderno. No se puede renombrar ni borrar.
    case none
}

enum NotebookList {
    /// Por fecha de creación, la más nueva arriba, y «Sin cuaderno» siempre al final.
    static func entries(_ notebooks: [Notebook]) -> [NotebookListEntry] {
        notebooks.sorted { $0.createdAt > $1.createdAt }.map { .notebook($0.id) } + [.none]
    }
}

/// La línea guardada, con sus expresiones subrayadas.
enum ExpressionHighlight {
    /// Rangos de cada `phrase` dentro de `english`, sin distinguir mayúsculas.
    static func ranges(of phrases: [String], in english: String) -> [Range<String.Index>] {
        phrases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { english.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) }
    }
}

/// Estudio › Cuadernos: cada cuaderno con lo que se guardó en él.
struct NotebooksSection: View {
    let store: NotebookStore
    @Query private var notebooks: [Notebook]
    @Query(filter: #Predicate<NotebookLine> { $0.isSaved }) private var savedLines: [NotebookLine]
    @State private var path: [NotebookListEntry] = []
    @State private var isCreating = false
    @State private var newName = ""
    @State private var newAbout = ""

    var body: some View {
        NavigationStack(path: $path) {
            List(NotebookList.entries(notebooks), id: \.self) { entry in
                NavigationLink(value: entry) { row(for: entry) }
            }
            .navigationTitle("Cuadernos")
            .navigationDestination(for: NotebookListEntry.self) { entry in
                NotebookDetailView(entry: entry, store: store) { path.removeAll() }
            }
            .toolbar {
                Button { isCreating = true } label: { Image(systemName: "plus") }
                    .help("Nuevo cuaderno")
            }
            .sheet(isPresented: $isCreating) { creationSheet }
        }
    }

    @ViewBuilder
    private func row(for entry: NotebookListEntry) -> some View {
        switch entry {
        case .notebook(let id):
            let notebook = notebooks.first { $0.id == id }
            let count = savedLines.filter { $0.notebook?.id == id }.count
            HStack {
                Label(notebook?.name ?? "", systemImage: "book.closed")
                Spacer()
                Text(count == 1 ? "1 guardada" : "\(count) guardadas").foregroundStyle(.secondary)
            }
        case .none:
            let count = savedLines.filter { $0.notebook == nil }.count
            HStack {
                Label("Sin cuaderno", systemImage: "tray").foregroundStyle(.secondary)
                Spacer()
                Text(count == 1 ? "1 guardada" : "\(count) guardadas").foregroundStyle(.secondary)
            }
        }
    }

    private var creationSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nuevo cuaderno").font(.headline)
            TextField("Nombre", text: $newName)
            TextField("De qué trata", text: $newAbout,
                      prompt: Text("Ej.: RPG de fantasía; Maren es la capitana…"), axis: .vertical)
                .lineLimit(2...4)
            HStack {
                Spacer()
                Button("Cancelar") { isCreating = false }
                Button("Crear") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let about = newAbout.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { _ = await store.createNotebook(name: name, about: about) }
                    newName = ""
                    newAbout = ""
                    isCreating = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
