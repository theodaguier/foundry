import SwiftUI

struct AccountView: View {
    @Environment(AppState.self) private var appState

    @State private var displayName: String = ""
    @State private var isEditingName = false
    @State private var isSaving = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

    private var initials: String {
        if let name = appState.userProfile?.displayName, !name.isEmpty {
            let parts = name.split(separator: " ")
            let first = parts.first.map { String($0.prefix(1)).uppercased() } ?? ""
            let last = parts.count > 1 ? String(parts.last!.prefix(1)).uppercased() : ""
            return first + last
        }
        if let email = appState.userProfile?.email {
            return String(email.prefix(1)).uppercased()
        }
        return "?"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                profileHeader
                sectionDivider
                infoSection
                sectionDivider
                planSection
                sectionDivider
                actionsSection
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .navigationTitle("Account")
        .alert("Delete Account", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("This will permanently delete your account and all associated data. This cannot be undone.")
        }
        .onAppear {
            displayName = appState.userProfile?.displayName ?? ""
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: FoundryTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color(.textBackgroundColor))
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle()
                            .strokeBorder(FoundryTheme.Colors.border, lineWidth: 1)
                    )
                Text(initials)
                    .font(FoundryTheme.Fonts.spaceGrotesk(24))
                    .foregroundStyle(FoundryTheme.Colors.textPrimary)
            }

            VStack(spacing: 4) {
                if let name = appState.userProfile?.displayName, !name.isEmpty {
                    Text(name.uppercased())
                        .font(FoundryTheme.Fonts.spaceGrotesk(20))
                        .tracking(1)
                        .foregroundStyle(FoundryTheme.Colors.textPrimary)
                }

                if let email = appState.userProfile?.email {
                    Text(email)
                        .font(FoundryTheme.Fonts.azeretMono(11))
                        .tracking(0.5)
                        .foregroundStyle(FoundryTheme.Colors.textSecondary)
                }
            }
        }
        .padding(.vertical, FoundryTheme.Spacing.xl)
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(spacing: 0) {
            row(label: "DISPLAY NAME") {
                if isEditingName {
                    HStack(spacing: 8) {
                        TextField("Your name", text: $displayName)
                            .font(FoundryTheme.Fonts.azeretMono(12))
                            .textFieldStyle(.plain)
                            .frame(maxWidth: 180)

                        Button("SAVE") { saveDisplayName() }
                            .font(FoundryTheme.Fonts.azeretMono(9))
                            .tracking(1)
                            .buttonStyle(.plain)
                            .foregroundStyle(FoundryTheme.Colors.textPrimary)
                            .disabled(isSaving)

                        Button("CANCEL") {
                            isEditingName = false
                            displayName = appState.userProfile?.displayName ?? ""
                        }
                        .font(FoundryTheme.Fonts.azeretMono(9))
                        .tracking(1)
                        .buttonStyle(.plain)
                        .foregroundStyle(FoundryTheme.Colors.textMuted)
                    }
                } else {
                    HStack(spacing: 8) {
                        Text(appState.userProfile?.displayName ?? "Not set")
                            .font(FoundryTheme.Fonts.azeretMono(12))
                            .foregroundStyle(
                                appState.userProfile?.displayName != nil
                                    ? FoundryTheme.Colors.textPrimary
                                    : FoundryTheme.Colors.textMuted
                            )

                        Spacer()

                        Button {
                            displayName = appState.userProfile?.displayName ?? ""
                            isEditingName = true
                        } label: {
                            Text("EDIT")
                                .font(FoundryTheme.Fonts.azeretMono(9))
                                .tracking(1)
                                .foregroundStyle(FoundryTheme.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            row(label: "EMAIL") {
                Text(appState.userProfile?.email ?? "—")
                    .font(FoundryTheme.Fonts.azeretMono(12))
                    .foregroundStyle(FoundryTheme.Colors.textPrimary)
                    .textSelection(.enabled)
                Spacer()
            }

            row(label: "MEMBER SINCE") {
                if let date = appState.userProfile?.createdAt {
                    Text(date, style: .date)
                        .font(FoundryTheme.Fonts.azeretMono(12))
                        .foregroundStyle(FoundryTheme.Colors.textPrimary)
                } else {
                    Text("—")
                        .font(FoundryTheme.Fonts.azeretMono(12))
                        .foregroundStyle(FoundryTheme.Colors.textMuted)
                }
                Spacer()
            }
        }
    }

    // MARK: - Plan Section

    private var planSection: some View {
        VStack(spacing: 0) {
            sectionHeader("PLAN")

            row(label: "CURRENT PLAN") {
                Text((appState.userProfile?.plan.rawValue ?? "free").uppercased())
                    .font(FoundryTheme.Fonts.azeretMono(12, weight: .medium))
                    .foregroundStyle(FoundryTheme.Colors.textPrimary)
                Spacer()
            }

            row(label: "PLUGINS GENERATED") {
                Text("\(appState.userProfile?.pluginsGenerated ?? 0)")
                    .font(FoundryTheme.Fonts.azeretMono(12))
                    .foregroundStyle(FoundryTheme.Colors.textPrimary)
                Spacer()
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 0) {
            // Sign out
            Button {
                Task { await appState.signOut() }
            } label: {
                HStack {
                    Text("SIGN OUT")
                        .font(FoundryTheme.Fonts.azeretMono(11))
                        .tracking(1.5)
                        .foregroundStyle(FoundryTheme.Colors.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.right.square")
                        .foregroundStyle(FoundryTheme.Colors.textSecondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color(.textBackgroundColor))
            }
            .buttonStyle(.plain)

            // Delete account
            Button {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Text("DELETE ACCOUNT")
                        .font(FoundryTheme.Fonts.azeretMono(11))
                        .tracking(1.5)
                        .foregroundStyle(FoundryTheme.Colors.trafficRed)
                    Spacer()
                    Image(systemName: "trash")
                        .foregroundStyle(FoundryTheme.Colors.trafficRed.opacity(0.6))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color(.textBackgroundColor))
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
        }
    }

    // MARK: - Reusable Components

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(FoundryTheme.Fonts.azeretMono(9))
                .tracking(2)
                .foregroundStyle(FoundryTheme.Colors.textMuted)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private func row<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(FoundryTheme.Fonts.azeretMono(9))
                .tracking(1.5)
                .foregroundStyle(FoundryTheme.Colors.textMuted)
            HStack {
                content()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.textBackgroundColor))
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(FoundryTheme.Colors.border)
            .frame(height: 1)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: FoundryTheme.Spacing.lg)
    }

    // MARK: - Actions

    private func saveDisplayName() {
        guard let userId = appState.userProfile?.id else { return }
        isSaving = true
        Task {
            do {
                try await AuthService.shared.updateProfile(userId: userId, displayName: displayName)
                appState.userProfile?.displayName = displayName
                isEditingName = false
            } catch {
                displayName = appState.userProfile?.displayName ?? ""
            }
            isSaving = false
        }
    }

    private func deleteAccount() {
        isDeleting = true
        Task {
            do {
                try await AuthService.shared.deleteAccount()
                await appState.signOut()
            } catch {
                isDeleting = false
            }
        }
    }
}
