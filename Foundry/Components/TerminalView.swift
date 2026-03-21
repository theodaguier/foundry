import SwiftUI

// MARK: - Terminal View

/// Terminal/log display panel with header and auto-scrolling content.
struct TerminalView: View {
    let title: String
    let logLines: [PipelineLogLine]
    let elapsedTime: String
    var streamingText: String = ""
    var showCursor: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            terminalHeader
            terminalBody
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

            Menu {
                Button("Copy Logs", systemImage: "doc.on.doc") {
                    copyLogs()
                }
                Button("Export as .txt…", systemImage: "square.and.arrow.up") {
                    exportLogs()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(FoundryTheme.Colors.textMuted)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, FoundryTheme.Spacing.lg)
        .frame(height: 40)
        .background(Color(.controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(.separatorColor)).frame(height: 1)
        }
    }

    // MARK: - Actions

    private var logsText: String {
        logLines.map { "[\($0.timestamp)] \($0.message)" }.joined(separator: "\n")
    }

    private func copyLogs() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logsText, forType: .string)
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "build-log.txt"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? logsText.write(to: url, atomically: true, encoding: .utf8)
            }
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
                                .foregroundStyle(Color.primary.opacity(0.35))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 2)
                        .id("streaming")
                    }

                    if showCursor {
                        Text("_")
                            .font(FoundryTheme.Fonts.jetBrainsMono(11))
                            .foregroundStyle(.primary)
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
                    .foregroundStyle(Color.primary.opacity(0.6))
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
                    .foregroundStyle(.primary)
                    .fontWeight(.bold)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .active:
                Text("->")
                    .font(FoundryTheme.Fonts.jetBrainsMono(11))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .lineLimit(1)
                    .frame(width: 82, alignment: .leading)
                    .padding(.top, 1)
                Text(line.message)
                    .font(FoundryTheme.Fonts.jetBrainsMono(11))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .error:
                Text("[ERR]")
                    .font(FoundryTheme.Fonts.jetBrainsMono(11))
                    .foregroundStyle(Color.red)
                    .lineLimit(1)
                    .frame(width: 82, alignment: .leading)
                    .padding(.top, 1)
                Text(line.message)
                    .font(FoundryTheme.Fonts.jetBrainsMono(11))
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
    }
}
