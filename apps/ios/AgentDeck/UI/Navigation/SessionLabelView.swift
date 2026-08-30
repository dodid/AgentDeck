import SwiftUI

struct SessionLabelView: View {
    let label: SessionDisplayLabel
    let secondaryColor: Color
    var badgeIcon: String = "person.fill"

    var body: some View {
        HStack(spacing: 0) {
            primaryBadge

            if let secondary = label.secondary, !secondary.isEmpty {
                separator
                secondaryLabel(secondary)
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 3)
        .background(AppTheme.panel.opacity(0.98))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var primaryBadge: some View {
        HStack(spacing: 0) {
            Image(systemName: badgeIcon)
                .font(.system(size: 11, weight: .semibold))
                .padding(.trailing, 1)
            badgeText
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
        .background(AppTheme.blue)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private var badgeText: some View {
        if label.primary.count > 8 {
            Text(label.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 72, alignment: .leading)
        } else {
            Text(label.primary)
                .lineLimit(1)
        }
    }

    private var separator: some View {
        Text(">")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.blue)
            .padding(.horizontal, 5)
            .layoutPriority(1)
    }

    private func secondaryLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(secondaryColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
    }
}
