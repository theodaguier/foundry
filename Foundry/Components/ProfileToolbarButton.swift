import SwiftUI

struct ProfileToolbarButton: View {
    @Environment(AppState.self) private var appState

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
        Button {
            appState.push(.account)
        } label: {
            ZStack {
                Circle()
                    .fill(.quaternary)
                    .frame(width: 24, height: 24)
                Text(initials)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}
