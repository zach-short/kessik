import Lottie
import SwiftUI

/// Shown once over the app at launch: the >_ mark from the icon draws in, then the view fades
/// out. The launch screen has the same background color, so the hand-off does not flash. A tap
/// skips it, and with Reduce Motion on, Lottie jumps to the end at once.
struct SplashView: View {
    var onFinish: () -> Void
    @State private var showName = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                LottieView(animation: .named("splash"))
                    .playing(loopMode: .playOnce)
                    .animationDidFinish { _ in onFinish() }
                    .resizable()
                    .frame(width: 220, height: 220)
                Text("kessik")
                    .font(.system(.subheadline, design: .monospaced).weight(.medium))
                    .tracking(3)
                    .foregroundStyle(Theme.textTertiary)
                    .opacity(showName ? 1 : 0)
                    .offset(y: -28)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onFinish)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeOut(duration: 0.4)) { showName = true }
        }
    }
}

#Preview {
    SplashView {}
}
