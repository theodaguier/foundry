import SwiftUI

// MARK: - Terminal View

/// Terminal/log display panel with header and auto-scrolling content.
struct TerminalView: View {
    let title: String
    let logLines: [PipelineLogLine]
    let elapsedTime: String
    var streamingText: String = ""
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

            Text(elapsedTime)
                .font(FoundryTheme.Fonts.jetBrainsMono(11))
                .tracking(1)
                .foregroundStyle(FoundryTheme.Colors.textMuted)
                .monospacedDigit()
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
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(logLines) { line in
                        TerminalLineView(line: line)
                            .id(line.id)
                    }

                    // Live streaming text — updates in place without creating new log entries
                    if !streamingText.isEmpty {
                        HStack(alignment: .top, spacing: 16) {
                            Text("…")
                                .font(FoundryTheme.Fonts.jetBrainsMono(11))
                                .foregroundStyle(FoundryTheme.Colors.textMuted.opacity(0.3))
                                .lineLimit(1)
                                .frame(width: 82, alignment: .leading)
                                .padding(.top, 1)
                            Text(streamingText)
                                .font(FoundryTheme.Fonts.jetBrainsMono(11))
                                .foregroundStyle(Color.white.opacity(0.35))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 2)
                        .id("streaming")
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
                withAnimation { proxy.scrollTo("cursor", anchor: .bottom) }
            }
            .onChange(of: streamingText) { _, _ in
                proxy.scrollTo("streaming", anchor: .bottom)
            }
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
                    .lineLimit(1)
                    .frame(width: 82, alignment: .leading)
                    .padding(.top, 1)
                Text(line.message)
                    .font(FoundryTheme.Fonts.jetBrainsMono(11))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .success:
                Text("[OK]")
                    .font(FoundryTheme.Fonts.jetBrainsMono(11))
                    .foregroundStyle(FoundryTheme.Colors.textMuted.opacity(0.4))
                    .lineLimit(1)
                    .frame(width: 82, alignment: .leading)
                    .padding(.top, 1)
                Text(line.message)
                    .font(FoundryTheme.Fonts.jetBrainsMono(11))
                    .foregroundStyle(.white)
                    .fontWeight(.bold)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .active:
                Text("->")
                    .font(FoundryTheme.Fonts.jetBrainsMono(11))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
                    .frame(width: 82, alignment: .leading)
                    .padding(.top, 1)
                Text(line.message)
                    .font(FoundryTheme.Fonts.jetBrainsMono(11))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .error:
                Text("[ERR]")
                    .font(FoundryTheme.Fonts.jetBrainsMono(11))
                    .foregroundStyle(Color(hex: 0xFF5F56))
                    .lineLimit(1)
                    .frame(width: 82, alignment: .leading)
                    .padding(.top, 1)
                Text(line.message)
                    .font(FoundryTheme.Fonts.jetBrainsMono(11))
                    .foregroundStyle(Color(hex: 0xFF5F56))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
    }
}
