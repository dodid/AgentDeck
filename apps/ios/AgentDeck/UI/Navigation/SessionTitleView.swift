import SwiftUI

struct SessionTitleView: View {
    let label: SessionDisplayLabel
    var isFetchingMessages: Bool = false
    var hasFetchError: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .overlay {
                    if isFetchingMessages {
                        Circle()
                            .stroke(AppTheme.blue.opacity(0.45), lineWidth: 4)
                            .scaleEffect(1.6)
                    }
                }
                .accessibilityLabel(statusLabel)
            SessionLabelView(
                label: label,
                secondaryColor: AppTheme.text
            )
        }
    }

    private var statusColor: Color {
        if isFetchingMessages { return AppTheme.blue }
        if hasFetchError { return AppTheme.red }
        return AppTheme.dim.opacity(0.35)
    }

    private var statusLabel: String {
        if isFetchingMessages { return String(localized: "Fetching messages") }
        if hasFetchError { return String(localized: "Message fetch failed") }
        return String(localized: "Messages up to date")
    }
}

#Preview {
    SessionTitleView(
        label: SessionDisplayLabel(primary: "main", secondary: "(gentle-pine-rv)"),
        isFetchingMessages: true
    )
}
