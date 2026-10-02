import ParlaCore

/// Un error de esta sesión. Se ve hasta que se descarta o se vuelve a arrancar
/// el modo. Lo pendiente de preparar no va aquí: eso es `SetupIssue`.
enum RuntimeNotice: Equatable, Identifiable, Sendable {
    case setup(String)
    case capture(String)
    case silentInput(String)
    case batch(String)

    var id: String {
        switch self {
        case .setup: "setup"
        case .capture: "capture"
        case .silentInput: "silentInput"
        case .batch: "batch"
        }
    }

    var text: String {
        switch self {
        case .setup(let text), .capture(let text), .silentInput(let text), .batch(let text): text
        }
    }
}

enum Notice: Equatable, Identifiable {
    case runtime(RuntimeNotice)
    case setup(SetupIssue)

    var id: String {
        switch self {
        case .runtime(let notice): "runtime-\(notice.id)"
        case .setup(let issue): "setup-\(issue.item)"
        }
    }
}

/// Lo que cabe en el menú emergente: primero lo que impide arrancar el modo
/// que acabas de pulsar, luego los errores de la sesión y luego el resto de
/// pendientes. Lo que no cabe se cuenta.
struct NoticeList: Equatable {
    let visible: [Notice]
    let hiddenCount: Int

    init(runtime: [RuntimeNotice], issues: [SetupIssue],
         priority: [SetupIssue] = [], limit: Int = 2) {
        let rest = issues.filter { !priority.contains($0) }
        let all = priority.map(Notice.setup) + runtime.map(Notice.runtime) + rest.map(Notice.setup)
        visible = Array(all.prefix(limit))
        hiddenCount = max(0, all.count - limit)
    }
}
