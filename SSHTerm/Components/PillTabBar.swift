import SwiftUI

struct PillTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selection = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 15, weight: .semibold))
                        if selection == tab {
                            Text(tab.title)
                                .font(.subheadline.weight(.semibold))
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .foregroundStyle(selection == tab ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background {
                        if selection == tab {
                            Capsule()
                                .fill(Theme.surfaceRaised)
                                .matchedGeometryEffect(id: "pill", in: highlight)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        .sensoryFeedback(.selection, trigger: selection)
    }
}
