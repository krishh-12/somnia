import SwiftUI

struct SomniaLogo: View {
    var draw: CGFloat
    var settled: CGFloat

    var body: some View {
        Image("SomniaMark")
            .resizable()
            .scaledToFit()
            .opacity(0.2 + 0.8 * max(settled, draw))
            .accessibilityLabel("somnia logo, two crescent moons joined by a heartbeat")
    }
}

struct OpeningView: View {
    var finish: () -> Void
    @State private var draw: CGFloat = 0
    @State private var settled: CGFloat = 0
    @State private var title = false

    var body: some View {
        ZStack {
            Color.black.opacity(1 - settled * 0.15)
            Night.background.opacity(settled)
            VStack(spacing: 18) {
                SomniaLogo(draw: draw, settled: settled)
                    .frame(width: 168, height: 168)
                    .scaleEffect(0.92 + settled * 0.08)
                Text("somnia")
                    .font(.somnia(size: 34, weight: .semibold))
                    .foregroundStyle(Night.pink.opacity(title ? 1 : 0))
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.25)) { draw = 1 }
            withAnimation(.easeInOut(duration: 1.15).delay(0.28)) { settled = 1 }
            withAnimation(.easeOut(duration: 0.45).delay(0.85)) { title = true }
            Task {
                try? await Task.sleep(for: .seconds(1.85))
                finish()
            }
        }
    }
}
