import SwiftUI

struct HomeView: View {
    let onChoosePhotos: () -> Void
    let onChooseFiles: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 700
            VStack(alignment: .leading, spacing: compact ? 12 : 18) {
                header
                hero(compact: compact)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VideoImportControls(onChoosePhotos: onChoosePhotos, onChooseFiles: onChooseFiles)
                workflow(compact: compact)
                footer
            }
            .padding(.horizontal, 21)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .hoopScreen()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 11) {
            HoopLogo(size: 40)
                .accessibilityHidden(true)
            Text("AI Highlights")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.hoopMint)
                .padding(11)
                .background(Color.hoopPanel, in: Circle())
                .accessibilityLabel(String(localized: "AI video analysis", bundle: AppLanguage.current.bundle))
        }
        .foregroundStyle(.white)
    }

    private func hero(compact: Bool) -> some View {
        Color.hoopPanel
            .overlay {
                Image("HomeHero")
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.28),
                        .init(color: Color.hoopInk.opacity(0.25), location: 0.52),
                        .init(color: Color.hoopInk.opacity(0.96), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.hoopMint).frame(width: 6, height: 6)
                        Text(String(localized: "YOUR GAME. YOUR STORY.", bundle: AppLanguage.current.bundle))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.8)
                            .foregroundStyle(Color.hoopMint)
                    }
                    Text(String(localized: "Every basket.\nWorth remembering.", bundle: AppLanguage.current.bundle))
                        .font(.system(size: compact ? 28 : 31, weight: .black, design: .rounded))
                        .tracking(-0.8)
                        .lineSpacing(0)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(localized: "AI finds your baskets and creates your personal highlights.", bundle: AppLanguage.current.bundle))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .padding(compact ? 19 : 22)
                .padding(.bottom, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            }
    }

    private func workflow(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Your highlights in 3 steps", bundle: AppLanguage.current.bundle))
                .font(.system(size: 17, weight: .bold, design: .rounded))
            HStack(spacing: 0) {
                workflowStep(number: "01", title: String(localized: "Import Video", bundle: AppLanguage.current.bundle), icon: "square.and.arrow.down")
                stepConnector
                workflowStep(number: "02", title: String(localized: "Review Shots", bundle: AppLanguage.current.bundle), icon: "viewfinder")
                stepConnector
                workflowStep(number: "03", title: String(localized: "Create Highlights", bundle: AppLanguage.current.bundle), icon: "film.stack")
            }
            .padding(.vertical, compact ? 10 : 12)
            .padding(.horizontal, 10)
            .background(Color.hoopPanel, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(Color.hoopStroke, lineWidth: 1)
            }
        }
    }

    private func workflowStep(number: String, title: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.hoopOrange)
                .frame(width: 32, height: 32)
                .background(Color.hoopOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
            Text(number)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(Color.hoopMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var stepConnector: some View {
        Rectangle()
            .fill(Color.white.opacity(0.13))
            .frame(width: 18, height: 1)
            .padding(.bottom, 32)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
            Text(String(localized: "Videos stay on your device. Nothing is uploaded.", bundle: AppLanguage.current.bundle))
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(Color.hoopMuted.opacity(0.8))
        .frame(maxWidth: .infinity)
    }
}
