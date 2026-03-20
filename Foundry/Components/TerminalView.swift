import SwiftUI

// MARK: - Terminal View

/// Terminal/log display panel with header and auto-scrolling content.
struct TerminalView: View {
    let title: String
    let logLines: [PipelineLogLine]
    let elapsedTime: String
    var showCursor: Bool = true

    @State private var cursorVisible = true

    var body: some View {
        VStack(spacing: 0) {
            terminalHeader
            terminalBody
        }
        .task {
            guard showCursor else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(600))
                cursorVisible.toggle()
            }
        }
    }

    // MARK: - Header

    private var terminalHeader: some View {
        HStack {
            HStack(spacing: 12) {
                Image(systemName: "terminal")
                    .font(.system(size: 10))
                    .foregroundStyle(FoundryTheme.Colors.textMuted)

                Text(title)
                    .font(FoundryTheme.Fonts.jetBrainsMono(10))
                    .tracking(1)
                    .foregroundStyle(FoundryTheme.Colors.textMuted)
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 4, height: 4)
                }
            }
        }
        .padding(.horizontal, FoundryTheme.Spacing.lg)
        .frame(height: 40)
        .background(Color.black.opacity(0.4))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
        }
    }

    // MARK: - Body

    private var terminalBody: some View {
        ZStack(alignment: .topTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(logLines) { line in
                            TerminalLineView(line: line)
                                .id(line.id)
                        }

                        if showCursor {
                            Text(cursorVisible ? "_" : " ")
                                .font(FoundryTheme.Fonts.jetBrainsMono(11))
                                .foregroundStyle(.white)
                                .id("cursor")
                        }
                    }
                    .padding(.horizontal, FoundryTheme.Spacing.xl)
                    .padding(.vertical, 31)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: logLines.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo("cursor", anchor: .bottom)
                    }
                }
            }

            // Elapsed time overlay
            Text(elapsedTime)
                .font(FoundryTheme.Fonts.jetBrainsMono(30))
                .tracking(-1.5)
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .background(.black.opacity(0.5))
                .padding(.top, 40)
                .padding(.trailing, 40)
        }
    }
}

// MARK: - Terminal Line

struct TerminalLineView: View {
    let line: PipelineLogLine

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            switch line.style {
            case .normal:
                Text(line.timestamp)
                    .font(FoundryTheme.Fonts.jetBrainsMono(11))
                    .foregroundStyle(FoundryTheme.Colors.textMuted.opacity(0.4))
                    .frame(width: 66, alignment: .leading)
                Text(line.message)
                    .font(FoundryTheme.Fonts.jetBrainsMono(11))
                    .foregroundStyle(Color.white.opacity(0.6))
            case .success:
                Text("[OK]")
                    .font(FoundryTheme.Fonts.jetBrainsMono(11))
                    .foregroundStyle(FoundryTheme.Colors.textMuted.opacity(0.4))
                    .frame(width: 66, alignment: .leading)
                Text(line.message)
                    .font(FoundryTheme.Fonts.jetBrainsMono(11))
                    .foregroundStyle(.white)
                    .fontWeight(.bold)
            case .active:
                Text("->")
                    .font(FoundryTheme.Fonts.jetBrainsMono(11))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 66, alignment: .leading)
                Text(line.message)
                    .font(FoundryTheme.Fonts.jetBrainsMono(11))
                    .foregroundStyle(.white)
            }
        }
        .frame(height: 18)
    }
}
