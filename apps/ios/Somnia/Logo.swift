import SwiftUI

struct SomniaLogo: View {
    var draw: CGFloat
    var settled: CGFloat

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.32
            let pink = Color(red: 0.96, green: 0.62, blue: 0.76)
            let pulseColor = Color(red: 1.0, green: 0.86, blue: 0.91)

            var glow = Path()
            glow.addEllipse(in: CGRect(
                x: center.x - radius * 1.35,
                y: center.y - radius * 1.35,
                width: radius * 2.7,
                height: radius * 2.7
            ))
            context.fill(glow, with: .color(pink.opacity(0.18 * settled)))

            var crescent = Path()
            crescent.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(48),
                endAngle: .degrees(312),
                clockwise: false
            )
            context.stroke(
                crescent,
                with: .color(pink.opacity(0.45 + 0.55 * settled)),
                style: StrokeStyle(lineWidth: radius * 0.16, lineCap: .round)
            )

            let steps = 90
            let shown = max(1, Int(draw * CGFloat(steps)))
            var pulse = Path()
            for step in 0 ... shown {
                let t = Double(step) / Double(steps)
                let angle = Angle.degrees(210 + t * 270).radians
                let spike = exp(-pow((t - 0.58) / 0.045, 2))
                let orbit = radius * (1.22 + spike * 0.55)
                let point = CGPoint(
                    x: center.x + CGFloat(cos(angle)) * orbit,
                    y: center.y + CGFloat(sin(angle)) * orbit
                )
                if step == 0 {
                    pulse.move(to: point)
                } else {
                    pulse.addLine(to: point)
                }
            }
            context.stroke(
                pulse,
                with: .color(pulseColor.opacity(0.45 + 0.55 * settled)),
                style: StrokeStyle(lineWidth: radius * 0.07, lineCap: .round, lineJoin: .round)
            )
        }
        .accessibilityLabel("Somnia logo, a moon wrapped around a pulse")
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
                Text("Somnia")
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
