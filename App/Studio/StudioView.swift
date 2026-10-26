import SwiftUI

/// La ventana principal: el historial y los ajustes, y más adelante el repaso
/// y la práctica, como filas nuevas de la barra lateral.
struct StudioView: View {
    @Bindable var state: AppState
    @Bindable var router: StudioRouter

    /// La lista solo lleva el Historial: Ajustes vive abajo, aparte.
    private var listSelection: Binding<StudioSection?> {
        Binding(get: { router.section },
                set: { if let section = $0 { router.section = section } })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: listSelection) {
                Label(StudioSection.history.title, systemImage: StudioSection.history.symbol)
                    .tag(StudioSection.history)
            }
            .safeAreaInset(edge: .bottom) {
                SidebarFooterButton(section: .settings, router: router)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            VStack(spacing: 0) {
                SetupBanner(setup: state.setup) { router.section = .settings }
                switch router.section {
                case .history: HistorySection()
                case .settings: SettingsSection(state: state)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .background {
            Button("Ajustes") { router.section = .settings }
                .keyboardShortcut(",", modifiers: .command)
                .hidden()
        }
        .task { await state.setup.refresh() }
    }
}

private struct SidebarFooterButton: View {
    let section: StudioSection
    @Bindable var router: StudioRouter

    var body: some View {
        Button { router.section = section } label: {
            Label(section.title, systemImage: section.symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(router.section == section ? Theme.accent.opacity(0.15) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(10)
    }
}
