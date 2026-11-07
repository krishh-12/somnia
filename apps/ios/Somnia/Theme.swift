import SwiftUI

enum Night {
    static let background = Color(red: 0.04, green: 0.06, blue: 0.12)
    static let card = Color(red: 0.09, green: 0.12, blue: 0.20)
    static let indigo = Color(red: 0.48, green: 0.45, blue: 0.98)
    static let teal = Color(red: 0.36, green: 0.86, blue: 0.82)
    static let pink = Color(red: 0.96, green: 0.62, blue: 0.76)
    static let text = Color.white
    static let muted = Color.white.opacity(0.68)
    static let danger = Color(red: 0.96, green: 0.38, blue: 0.45)
}

struct NightCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Night.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
