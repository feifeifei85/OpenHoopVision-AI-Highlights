import SwiftUI

struct SwipeToDeleteRow<Content: View>: View {
    let id: String
    @Binding var revealedRow: String?
    var onRetry: (() -> Void)? = nil
    let onDelete: () -> Void
    var deleteLabel = String(localized: "Delete Video", bundle: AppLanguage.current.bundle)
    @ViewBuilder let content: () -> Content
    @State private var isRevealed = false
    @State private var isClosingReveal = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    content()
                        .containerRelativeFrame(.horizontal)
                        .id("card")
                    HStack(spacing: 12) {
                        if let onRetry {
                            AnalysisRetryButton(size: 56, hitTargetSize: 68) {
                                closeReveal(using: proxy, completion: onRetry)
                            }
                                .accessibilityIdentifier("retry.\(id)")
                        }
                        Button(role: .destructive, action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.red, in: Circle())
                                .frame(width: 68, height: 56)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(deleteLabel)
                        .accessibilityIdentifier("delete.\(id)")
                        .id("delete")
                    }
                }
                .scrollTargetLayout()
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: HorizontalScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .global).minX
                        )
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(DeleteRevealBehavior(revealWidth: onRetry == nil ? 80 : 160))
            .modifier(HorizontalSwipeOffsetObserver { handleRevealChange($0) })
            .onChange(of: revealedRow) { _, value in
                if value != id, isRevealed { closeReveal(using: proxy) }
            }
        }
        .accessibilityAction(named: String(localized: "Delete", bundle: AppLanguage.current.bundle), onDelete)
    }

    private func closeReveal(using proxy: ScrollViewProxy, completion: (() -> Void)? = nil) {
        if isClosingReveal {
            guard let completion else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                completion()
            }
            return
        }
        isClosingReveal = true
        if revealedRow == id { revealedRow = nil }
        withAnimation(.snappy) { proxy.scrollTo("card", anchor: .leading) }
        guard let completion else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            isClosingReveal = false
            completion()
        }
    }

    private func handleRevealChange(_ isRevealed: Bool) {
        guard self.isRevealed != isRevealed else { return }
        self.isRevealed = isRevealed

        if isRevealed {
            if !isClosingReveal, revealedRow != id { revealedRow = id }
        } else {
            if isClosingReveal { isClosingReveal = false }
            if revealedRow == id { revealedRow = nil }
        }
    }
}

private struct HorizontalScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct HorizontalSwipeOffsetObserver: ViewModifier {
    let onRevealChange: (Bool) -> Void
    @State private var initialFrameX: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.x > 4
            } action: { _, isRevealed in
                onRevealChange(isRevealed)
            }
        } else {
            content.onPreferenceChange(HorizontalScrollOffsetPreferenceKey.self) { frameX in
                let initialX = initialFrameX ?? frameX
                if initialFrameX == nil { initialFrameX = frameX }
                onRevealChange(initialX - frameX > 4)
            }
        }
    }
}

struct AnalysisRetryButton: View {
    var size: CGFloat = 56
    var hitTargetSize: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: size * 0.39, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.hoopOrange, in: Circle())
                .frame(width: max(size, hitTargetSize), height: max(size, hitTargetSize))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Analyze video again", bundle: AppLanguage.current.bundle))
    }
}

private struct DeleteRevealBehavior: ScrollTargetBehavior {
    let revealWidth: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let offset = target.rect.minX > revealWidth / 2 ? revealWidth : 0
        target.rect = CGRect(origin: CGPoint(x: offset, y: 0), size: context.containerSize)
        target.anchor = .topLeading
    }
}
