import SwiftUI

// MARK: - Refine View (Modify Plugin — matches PromptView design)

struct RefineView: View {
    @Environment(AppState.self) private var appState
    let plugin: Plugin

    @State private var modification = ""
    @State private var selectedModel: AgentModel = ModelCatalog.defaultModel
    @FocusState private var isFocused: Bool

    private var isEmpty: Bool {
        modification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 80)
            contentCanvas
                .frame(maxWidth: 1024)
            Spacer(minLength: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Refine")
        .onAppear { isFocused = true }
    }

    // MARK: - Content Canvas

    private var contentCanvas: some View {
        VStack(spacing: 0) {
            Spacer()

            heroSection
                .padding(.bottom, 32)

            promptSection

            Spacer()
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "slider.horizontal.below.rectangle")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(.primary.opacity(0.7))

            Text("Describe what you want to change.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(
                "Add a low-pass filter with resonance control…",
                text: $modification,
                axis: .vertical
            )
            .font(.system(size: 14))
            .focused($isFocused)
            .lineLimit(5...10)
            .textFieldStyle(.plain)
            .padding(12)
            .frame(minHeight: 100, alignment: .topLeading)
            .background(Color(.textBackgroundColor).opacity(0.5), in: .rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(.separatorColor).opacity(0.6), lineWidth: 1)
            )

            HStack(spacing: 10) {
                modelPicker

                Spacer()

                Button("Refine") { refine() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(isEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
                .disabled(isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.top, 10)
        }
    }

    // MARK: - Model Picker

    private var selectedProvider: AgentProvider {
        ModelCatalog.provider(for: selectedModel)
    }

    private var modelPicker: some View {
        Menu {
            ForEach(ModelCatalog.providers) { provider in
                Section {
                    ForEach(provider.models) { model in
                        Button {
                            selectedModel = model
                        } label: {
                            HStack {
                                Text(model.displayName)
                                Text("— \(model.subtitle)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Label(provider.name, image: provider.icon)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(selectedProvider.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)

                Text(selectedModel.displayName)
                    .font(.system(size: 12, weight: .medium))

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.controlBackgroundColor), in: .rect(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func refine() {
        guard !isEmpty else { return }
        let config = RefineConfig(
            plugin: plugin,
            modification: modification
        )
        appState.push(.refinement(config: config))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        RefineView(plugin: Plugin.samplePlugins[0])
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
