import SwiftUI

// MARK: - Foundry Header Bar

/// Reusable top navigation bar used across main screens.
/// Displays the FOUNDRY logo, filter tabs, and trailing action content.
struct FoundryHeaderBar<TrailingContent: View>: View {
    let activeFilter: PluginFilter?
    let onFilterTap: ((PluginFilter) -> Void)?
    let onLogoTap: () -> Void
    @ViewBuilder let trailingContent: () -> TrailingContent

    init(
        activeFilter: PluginFilter? = nil,
        onFilterTap: ((PluginFilter) -> Void)? = nil,
        onLogoTap: @escaping () -> Void,
        @ViewBuilder trailingContent: @escaping () -> TrailingContent = { EmptyView() }
    ) {
        self.activeFilter = activeFilter
        self.onFilterTap = onFilterTap
        self.onLogoTap = onLogoTap
        self.trailingContent = trailingContent
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onLogoTap) {
                Text("FOUNDRY")
                    .font(FoundryTheme.Fonts.spaceGrotesk(18))
                    .tracking(1)
                    .foregroundStyle(FoundryTheme.Colors.textPrimary)
            }
            .buttonStyle(.plain)

            if let onFilterTap {
                FilterTabBar(
                    activeFilter: activeFilter,
                    onTap: onFilterTap
                )
                .padding(.leading, FoundryTheme.Spacing.xxl)
            }

            Spacer()

            trailingContent()
        }
        .padding(.horizontal, FoundryTheme.Spacing.lg)
        .frame(height: FoundryTheme.Layout.headerHeight)
        .background(FoundryTheme.Colors.backgroundToolbar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FoundryTheme.Colors.border)
                .frame(height: FoundryTheme.Layout.borderWidth)
        }
    }
}

// MARK: - Filter Tab Bar

/// Horizontal row of filter tabs used in the header bar.
struct FilterTabBar: View {
    let activeFilter: PluginFilter?
    let onTap: (PluginFilter) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PluginFilter.allCases, id: \.self) { filter in
                FilterTab(
                    label: filter.rawValue,
                    isActive: activeFilter == filter,
                    action: { onTap(filter) }
                )
                .padding(.leading, filter == .all ? 0 : FoundryTheme.Spacing.lg)
            }
        }
    }
}

// MARK: - Filter Tab

/// A single tab button with an active underline indicator.
struct FilterTab: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(label)
                    .font(FoundryTheme.Fonts.azeretMono(11))
                    .tracking(0.5)
                    .foregroundStyle(isActive ? FoundryTheme.Colors.textPrimary : FoundryTheme.Colors.textSecondary)
                    .frame(height: 44)
                Rectangle()
                    .fill(isActive ? Color.primary : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Primary Action Button

/// White-on-black action button used in headers (GENERATE, + NEW, etc.)
struct FoundryActionButton: View {
    let title: String
    let action: () -> Void
    var isDisabled: Bool = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FoundryTheme.Fonts.azeretMono(12))
                .tracking(0.5)
                .foregroundStyle(Color(.windowBackgroundColor))
                .padding(.horizontal, FoundryTheme.Spacing.lg)
                .padding(.vertical, FoundryTheme.Spacing.xs)
                .background(Color.primary)
                .clipShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
    }
}
