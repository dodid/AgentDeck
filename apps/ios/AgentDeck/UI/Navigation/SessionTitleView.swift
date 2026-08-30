import SwiftUI

struct SessionTitleView: View {
    let label: SessionDisplayLabel
    var isFetchingMessages: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isFetchingMessages ? AppTheme.blue : AppTheme.dim.opacity(0.35))
                .frame(width: 8, height: 8)
                .overlay {
                    if isFetchingMessages {
                        Circle()
                            .stroke(AppTheme.blue.opacity(0.45), lineWidth: 4)
                            .scaleEffect(1.6)
                    }
                }
            SessionLabelView(
                label: label,
                secondaryColor: AppTheme.text
            )
        }
    }
}

#Preview {
    SessionTitleView(
        label: SessionDisplayLabel(primary: "main", secondary: "(gentle-pine-rv)"),
        isFetchingMessages: true
    )
}
