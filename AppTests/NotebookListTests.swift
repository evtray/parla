import Testing
import Foundation
@testable import Parla

@Test func sinCuadernoVaSiempreAlFinal() {
    let old = Notebook(name: "Viejo", about: "", createdAt: Date(timeIntervalSince1970: 1))
    let new = Notebook(name: "Nuevo", about: "", createdAt: Date(timeIntervalSince1970: 2))
    #expect(NotebookList.entries([old, new]) == [.notebook(new.id), .notebook(old.id), .none])
    #expect(NotebookList.entries([]) == [.none])
}

@Test func resaltaLaExpresionSinImportarMayusculas() {
    let english = "We have to Hold the line until dawn."
    let ranges = ExpressionHighlight.ranges(of: ["hold the line"], in: english)
    #expect(ranges.map { String(english[$0]) } == ["Hold the line"])
}

@Test func unaExpresionQueNoApareceNoResaltaNada() {
    #expect(ExpressionHighlight.ranges(of: ["piece of cake", ""],
                                       in: "We have to hold the line.").isEmpty)
}
