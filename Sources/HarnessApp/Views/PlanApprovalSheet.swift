import SwiftUI

/// Native plan approval sheet shown when the agent calls ExitPlanMode.
/// Displays the plan content and provides Accept / Reject / Modify actions.
struct PlanApprovalSheet: View {
    let plan: String
    let onAccept: () -> Void
    let onReject: (String) -> Void

    @State private var feedback: String = ""
    @State private var showFeedbackField: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
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
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // Plan content
            ScrollView {
                Text(plan)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .frame(maxHeight: 280)

            Divider()

            // Feedback field (shown when rejecting)
            if showFeedbackField {
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

            // Actions
            HStack(spacing: 12) {
                if showFeedbackField {
                    Button("Cancel") {
                        showFeedbackField = false
                        feedback = ""
                    }
                    .buttonStyle(.bordered)

                    Button("Send Feedback") {
                        onReject(feedback)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Reject") {
                        showFeedbackField = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button("Approve Plan") {
                        onAccept()
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
        .frame(width: 560)
    }
}