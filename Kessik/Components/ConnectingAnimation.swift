import Lottie
import SwiftUI

/// A key and a padlock with coral packets moving between them. It loops while `active` and
/// rests, dimmed, when not.
struct ConnectingAnimation: View {
    var active = true

    var body: some View {
        LottieView(animation: .named("connecting"))
            .playbackMode(active
                ? .playing(.fromProgress(nil, toProgress: 1, loopMode: .loop))
                : .paused(at: .progress(0.15)))
            .resizable()
            .frame(width: 216, height: 72)
            .opacity(active ? 1 : 0.5)
            .animation(.easeOut(duration: 0.25), value: active)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 24) {
        ConnectingAnimation()
        ConnectingAnimation(active: false)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.background)
}
