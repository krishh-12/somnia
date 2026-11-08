import SwiftUI
import UIKit

extension Font {
    /// Fraunces, a soft serif. Display sizes get a little play; body text stays even.
    static func somnia(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        somnia(size: Night.points(for: style), weight: weight)
    }

    static func somnia(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font(Night.face(size: size, weight: Night.axisWeight(weight)))
    }
}

enum Night {
    static let backgroundRed: CGFloat = 0.16
    static let backgroundGreen: CGFloat = 0.18
    static let backgroundBlue: CGFloat = 0.26
    static let background = Color(red: backgroundRed, green: backgroundGreen, blue: backgroundBlue)
    static let well = Color(red: 0.11, green: 0.13, blue: 0.20)
    static let indigo = Color(red: 0.48, green: 0.45, blue: 0.98)
    static let teal = Color(red: 0.36, green: 0.86, blue: 0.82)
    static let pink = Color(red: 0.96, green: 0.62, blue: 0.76)
    static let text = Color.white
    static let muted = Color.white.opacity(0.68)
    static let danger = Color(red: 0.96, green: 0.38, blue: 0.45)
    static let shade = Color.black.opacity(0.55)
    static let highlight = Color.white.opacity(0.10)
    static let uiBackground = UIColor(red: backgroundRed, green: backgroundGreen, blue: backgroundBlue, alpha: 1)

    static func face(size: CGFloat, weight: CGFloat) -> UIFont {
        let axes: [NSNumber: NSNumber] = [
            0x6F70737A: NSNumber(value: Double(min(144, max(9, size)))),
            0x77676874: NSNumber(value: Double(weight)),
            0x534F4654: 50,
            0x574F4E4B: NSNumber(value: size >= 28 ? 1.0 : 0.0),
        ]
        let described = UIFontDescriptor(fontAttributes: [.family: "Fraunces"]).addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: "NSCTFontVariationAttribute"): axes,
        ])
        let font = UIFont(descriptor: described, size: size)
        if font.familyName == "Fraunces" || font.fontName.localizedCaseInsensitiveContains("fraunces") {
            return font
        }
        return .systemFont(ofSize: size, weight: .medium)
    }

    static func axisWeight(_ weight: Font.Weight) -> CGFloat {
        if weight == .bold || weight == .heavy || weight == .black { return 700 }
        if weight == .semibold { return 600 }
        if weight == .medium { return 520 }
        if weight == .light || weight == .thin || weight == .ultraLight { return 340 }
        return 450
    }

    static func points(for style: Font.TextStyle) -> CGFloat {
        let textStyle: UIFont.TextStyle
        switch style {
        case .largeTitle: textStyle = .largeTitle
        case .title: textStyle = .title1
        case .title2: textStyle = .title2
        case .title3: textStyle = .title3
        case .headline: textStyle = .headline
        case .subheadline: textStyle = .subheadline
        case .callout: textStyle = .callout
        case .footnote: textStyle = .footnote
        case .caption: textStyle = .caption1
        case .caption2: textStyle = .caption2
        default: textStyle = .body
        }
        return UIFont.preferredFont(forTextStyle: textStyle).pointSize
    }

    static let reveal = Animation.spring(response: 0.46, dampingFraction: 0.68)
}

struct NightCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neuRaised()
    }
}

struct NeuButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? Color(red: 0.18, green: 0.10, blue: 0.16) : Night.pink)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(prominent ? Night.pink : Night.background)
                    .shadow(color: configuration.isPressed ? .clear : Night.shade, radius: 8, x: 5, y: 5)
                    .shadow(color: configuration.isPressed ? .clear : Night.highlight, radius: 8, x: -4, y: -4)
            }
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

extension View {
    func neuRaised(radius: CGFloat = 24) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Night.background)
                .shadow(color: Night.shade, radius: 10, x: 7, y: 7)
                .shadow(color: Night.highlight, radius: 10, x: -6, y: -6)
        }
    }

    func neuInset(radius: CGFloat = 16) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Night.well)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Night.shade.opacity(0.9), lineWidth: 3)
                        .blur(radius: 2)
                        .offset(x: 1.5, y: 1.5)
                        .mask {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                        }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Night.highlight.opacity(0.7), lineWidth: 2)
                        .blur(radius: 1.5)
                        .offset(x: -1, y: -1)
                        .mask {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                        }
                }
        }
    }
}
