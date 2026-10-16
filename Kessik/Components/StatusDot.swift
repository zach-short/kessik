import SwiftUI

struct StatusDot: View {
    var status: Host.Status

    private var color: Color {
        switch status {
        case .online: Theme.online
        case .unreachable: Theme.warning
        case .unknown: Theme.offline
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(status == .online ? 0.8 : 0), radius: 4)
            .accessibilityLabel(status.rawValue)
    }
}
