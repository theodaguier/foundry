import SwiftUI

struct QuickOptionsView: View {
    @Environment(AppState.self) private var appState
    let prompt: String

    @State private var format: FormatOption = .both
    @State private var channelLayout: ChannelLayout = .stereo
    @State private var presetCount: PresetCount = .five

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(prompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 8))

                Form {
                    Picker("Format", selection: $format) {
                        ForEach(FormatOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Channels", selection: $channelLayout) {
                        ForEach(ChannelLayout.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Presets", selection: $presetCount) {
                        ForEach(PresetCount.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
            }
            .padding(20)
            .frame(maxWidth: 500, alignment: .leading)
        }
        .navigationTitle("Options")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Skip") {
                    startGeneration()
                }
                .buttonStyle(.glass)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Generate") {
                    startGeneration()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private func startGeneration() {
        let config = GenerationConfig(
            prompt: prompt,
            format: format,
            channelLayout: channelLayout,
            presetCount: presetCount
        )
        appState.push(.generation(config: config))
    }
}

#Preview {
    NavigationStack {
        QuickOptionsView(prompt: "A warm analog synth with detuned oscillators")
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
