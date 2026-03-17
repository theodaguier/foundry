import SwiftUI

struct StepListView: View {
    let steps: [GenerationStep]
    let currentStep: GenerationStep
    let completedSteps: Set<Int>
    let buildAttempt: Int

    var body: some View {
        VStack(spacing: 2) {
            ForEach(steps, id: \.self) { step in
                HStack(spacing: 10) {
                    stepIndicator(for: step)
                        .frame(width: 16)

                    Image(systemName: step.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(stepColor(for: step))
                        .frame(width: 16)

                    Text(step.label)
                        .font(.subheadline)
                        .foregroundStyle(stepColor(for: step))

                    Spacer()

                    if completedSteps.contains(step.rawValue) {
                        Text("Done")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    step == currentStep
                        ? Color.accentColor.opacity(0.06)
                        : Color.clear,
                    in: .rect(cornerRadius: 6)
                )
            }
        }
        .padding(4)
        .background(Color(.controlBackgroundColor).opacity(0.3), in: .rect(cornerRadius: 10))
    }

    @ViewBuilder
    private func stepIndicator(for step: GenerationStep) -> some View {
        if completedSteps.contains(step.rawValue) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.green)
        } else if step == currentStep {
            ProgressView()
                .controlSize(.mini)
        } else if step.rawValue > currentStep.rawValue {
            Circle()
                .fill(.quaternary)
                .frame(width: 6, height: 6)
        } else {
            EmptyView()
        }
    }

    private func stepColor(for step: GenerationStep) -> some ShapeStyle {
        if completedSteps.contains(step.rawValue) {
            return .tertiary
        } else if step == currentStep {
            return .primary
        } else {
            return .quaternary
        }
    }
}
