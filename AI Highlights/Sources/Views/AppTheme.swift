import SwiftUI

struct HoopLogo: View {
    let size: CGFloat

    var body: some View {
        Image("AIHighlightsLogo")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .accessibilityLabel(String(localized: "AI Highlights logo", bundle: AppLanguage.current.bundle))
    }
}

extension Color {
    static let hoopInk = Color(red: 0.035, green: 0.047, blue: 0.063)
    static let hoopPanel = Color(red: 0.075, green: 0.09, blue: 0.11)
    static let hoopElevated = Color(red: 0.12, green: 0.14, blue: 0.16)
    static let hoopOrange = Color(red: 1.0, green: 0.39, blue: 0.13)
    static let hoopMint = Color(red: 0.28, green: 0.89, blue: 0.72)
    static let hoopMuted = Color(red: 0.59, green: 0.64, blue: 0.68)
    static let hoopStroke = Color.white.opacity(0.09)
}

struct HoopScreen: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.hoopInk.ignoresSafeArea())
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

extension View {
    func hoopScreen() -> some View { modifier(HoopScreen()) }
}

struct HoopPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                LinearGradient(
                    colors: [Color.hoopOrange, Color(red: 0.93, green: 0.25, blue: 0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(.white.opacity(configuration.isPressed ? 0.04 : 0.17), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
