import SwiftUI

/// Native plan approval sheet shown when the agent calls ExitPlanMode.
/// Displays the plan content and provides Accept / Reject / Modify actions.
///
/// Owns its actions per the SwiftUI sheet pattern: reads the bridge from
/// @Environment, executes the decision, then dismisses itself. The parent
/// only needs to drive `.sheet(item:)` with the proposal.
struct PlanApprovalSheet: View {
    let plan: String

    @Environment(HarnessStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var feedback: String = ""
    @State private var showFeedbackField: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            planContent
            Divider()
            if showFeedbackField {
                feedbackField
            }
            actions
        }
        .frame(width: 560)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Plan Proposed")
                    .font(.title3.bold())
                Text("The agent has presented a plan for your approval.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Plan-length badge: lines × words gives a quick size hint
            let lines = plan.split(separator: "\n").count
            Label("\(lines)", systemImage: "text.alignleft")
                .font(.caption2.bold().monospacedDigit())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.tint.opacity(0.1), in: Capsule())
                .help("\(lines) lines in plan")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var planContent: some View {
        ScrollView {
            Text(plan)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.orange.opacity(0.15), lineWidth: 1)
                )
        }
        .frame(maxHeight: 280)
    }

    @ViewBuilder
    private var feedbackField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Feedback for revision:")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextEditor(text: $feedback)
                .font(.system(.body))
                .frame(minHeight: 60, maxHeight: 100)
                .padding(6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 12) {
            if showFeedbackField {
                Button("Cancel", action: cancelFeedback)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape, modifiers: [])

                Button("Send Feedback", action: sendFeedback)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            } else {
                Button("Reject", role: .destructive, action: startFeedback)
                    .buttonStyle(.bordered)
                    .tint(.red)

                Spacer()
                Button {
                    approve()
                } label: {
                    Label("Approve Plan", systemImage: "checkmark.circle.fill")
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 20)
    }

    // MARK: - Actions

    private func approve() {
        Task { @MainActor in
            store.bridge.approvePlan()
            dismiss()
        }
    }

    private func startFeedback() {
        showFeedbackField = true
    }

    private func cancelFeedback() {
        showFeedbackField = false
        feedback = ""
    }

    private func sendFeedback() {
        let trimmed = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { @MainActor in
            store.bridge.rejectPlan(feedback: trimmed)
            dismiss()
        }
    }
}