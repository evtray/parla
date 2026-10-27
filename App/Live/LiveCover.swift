import SwiftUI

/// C: tapa el recuadro con la traducción, como si el juego estuviera en español.
struct LiveCover: View {
    let session: LiveSession

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if let spanish = session.latestSpanish {
                Text(spanish)
                    .font(.system(size: 22, weight: .medium))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.4)
                    .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
