import Foundation
import StoreKit
import SwiftUI

struct PaywallView: View {
    let controller: SubscriptionController
    private let termsURL = URL(string: "https://agentdeck.candiapps.com/terms.html")
    private let privacyURL = URL(string: "https://agentdeck.candiapps.com/privacy.html")

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var purchasingProductID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    heroCard

                    if controller.isLoadingProducts && controller.products.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else if controller.products.isEmpty {
                        unavailableState
                    } else {
                        VStack(spacing: 10) {
                            ForEach(controller.products, id: \.id) { product in
                                offerCard(for: product)
                            }
                        }
                    }

                    if let errorMessage = controller.errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(AppTheme.font(.footnote, size: .medium))
                            .foregroundStyle(AppTheme.red)
                    }

                    footerActions
                }
                .padding(16)
            }
            .background(AppTheme.bg)
            .navigationTitle(String(localized: "AgentDeck Plus"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Close")) {
                        dismiss()
                    }
                }
            }
            .task {
                await controller.start()
            }
            .onChange(of: controller.hasUnlockedAgentAccess) { _, unlocked in
                if unlocked {
                    dismiss()
                }
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Unlock Every Agent")
                    .font(AppTheme.font(.title3, size: .medium, weight: .bold))
                    .foregroundStyle(AppTheme.text)

                Text("Use AgentDeck with your own Cloudflare R2 relay. Normal AgentDeck usage stays within Cloudflare R2's free tier, so there is no extra R2 cost for typical use.")
                    .font(AppTheme.font(.subheadline, size: .medium))
                    .foregroundStyle(AppTheme.dim)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    compactTag(icon: "cloud.fill", text: "R2 stays free")
                    compactTag(icon: "bubble.left.and.bubble.right.fill", text: "Stay in sync")
                }
                compactTag(icon: "iphone.and.ipad.landscape", text: "One subscription, all your devices")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    AppTheme.panel,
                    AppTheme.blue.opacity(0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var footerActions: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    await controller.restorePurchases()
                    if controller.hasUnlockedAgentAccess {
                        dismiss()
                    }
                }
            } label: {
                HStack {
                    Spacer()
                    if controller.isRestoring {
                        ProgressView()
                    } else {
                        Text("Restore Purchases")
                    }
                    Spacer()
                }
                .font(AppTheme.font(.body, size: .medium, weight: .semibold))
                .foregroundStyle(AppTheme.blue)
            }
            .disabled(controller.isPurchasing || controller.isRestoring)
            .padding(.top, 4)

            if controller.hasUnlockedAgentAccess, let manageURL = controller.manageSubscriptionsURL {
                Button("Manage Subscription") {
                    openURL(manageURL)
                }
                .font(AppTheme.font(.body, size: .medium, weight: .semibold))
                .foregroundStyle(AppTheme.dim)
            }

            Text("Cancel anytime in your App Store subscriptions")
                .font(AppTheme.font(.footnote, size: .medium))
                .foregroundStyle(AppTheme.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack(spacing: 16) {
                if let termsURL {
                    Button("Terms of Service") {
                        openURL(termsURL)
                    }
                }

                if let privacyURL {
                    Button("Privacy Policy") {
                        openURL(privacyURL)
                    }
                }
            }
            .font(AppTheme.font(.footnote, size: .medium, weight: .semibold))
            .foregroundStyle(AppTheme.blue)
        }
        .padding(.top, 4)
    }

    private var unavailableState: some View {
        VStack(spacing: 12) {
            Text("Subscriptions are temporarily unavailable.")
                .font(AppTheme.font(.subheadline, size: .medium, weight: .semibold))
                .foregroundStyle(AppTheme.text)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Button(String(localized: "Try Again")) {
                Task {
                    await controller.refreshProducts()
                }
            }
            .font(AppTheme.font(.body, size: .medium, weight: .semibold))
            .foregroundStyle(AppTheme.blue)
            .disabled(controller.isLoadingProducts || controller.isPurchasing || controller.isRestoring)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    private func offerCard(for product: Product) -> some View {
        let isRecommended = product.id == controller.recommendedProductID
        let isBusy = controller.isPurchasing || controller.isRestoring

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(title(for: product))
                            .font(AppTheme.font(.headline, size: .medium, weight: .bold))
                            .foregroundStyle(AppTheme.text)

                        if isRecommended {
                            Text("Best value")
                                .font(AppTheme.font(.caption, size: .medium, weight: .semibold))
                                .foregroundStyle(AppTheme.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.blue.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    Text(productDetailText(for: product))
                        .font(AppTheme.font(.subheadline, size: .medium))
                        .foregroundStyle(AppTheme.dim)

                    Text(priceSummary(for: product))
                        .font(AppTheme.font(.title3, size: .medium, weight: .bold))
                        .foregroundStyle(AppTheme.text)

                    if let caption = secondaryPriceSummary(for: product) {
                        Text(caption)
                            .font(AppTheme.font(.subheadline, size: .medium))
                            .foregroundStyle(AppTheme.dim)
                    }
                }

                Spacer(minLength: 12)
            }

            Button {
                Task {
                    purchasingProductID = product.id
                    let didUnlock = await controller.purchase(product)
                    purchasingProductID = nil
                    if didUnlock {
                        dismiss()
                    }
                }
            } label: {
                HStack {
                    Spacer()
                    if purchasingProductID == product.id && controller.isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(primaryActionTitle(for: product))
                    }
                    Spacer()
                }
                .font(AppTheme.font(.body, size: .medium, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.vertical, 12)
                .background(isRecommended ? AppTheme.blue : AppTheme.text)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(isBusy)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panel)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(isRecommended ? AppTheme.blue : AppTheme.border, lineWidth: isRecommended ? 2 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func compactTag(icon: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.blue)
            Text(text)
                .font(AppTheme.font(.footnote, size: .medium, weight: .semibold))
                .foregroundStyle(AppTheme.text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.panel.opacity(0.7))
        .clipShape(Capsule())
    }

    private func title(for product: Product) -> String {
        switch product.id {
        case SubscriptionController.monthlyProductID:
            return String(localized: "Monthly")
        case SubscriptionController.yearlyProductID:
            return String(localized: "Yearly")
        default:
            return product.displayName
        }
    }

    private func productDetailText(for product: Product) -> String {
        switch product.id {
        case SubscriptionController.yearlyProductID:
            return String(localized: "Best price if you use AgentDeck regularly")
        case SubscriptionController.monthlyProductID:
            return String(localized: "Flexible monthly billing")
        default:
            return product.description
        }
    }

    private func priceSummary(for product: Product) -> String {
        guard let period = periodLabel(for: product) else {
            return product.displayPrice
        }
        return "\(product.displayPrice) / \(period)"
    }

    private func secondaryPriceSummary(for product: Product) -> String? {
        if product.id == SubscriptionController.yearlyProductID, let discountPercentage = yearlyDiscountPercentage(for: product) {
            let format = String(localized: "%@%% discount")
            return String(format: format, String(discountPercentage))
        }

        if let periodDetail = renewalDetail(for: product) {
            return periodDetail
        }

        return nil
    }

    private func primaryActionTitle(for product: Product) -> String {
        let format = String(localized: "Start %@ for %@")
        return String(format: format, title(for: product), product.displayPrice)
    }

    private func periodLabel(for product: Product) -> String? {
        guard let subscription = product.subscription else { return nil }
        let period = subscription.subscriptionPeriod

        switch (period.unit, period.value) {
        case (.month, 1):
            return String(localized: "month")
        case (.year, 1):
            return String(localized: "year")
        default:
            return nil
        }
    }

    private func renewalDetail(for product: Product) -> String? {
        guard let period = periodLabel(for: product) else { return nil }
        let format = String(localized: "Renews every %@")
        return String(format: format, period)
    }

    private func yearlyDiscountPercentage(for product: Product) -> Int? {
        guard let subscription = product.subscription else { return nil }
        guard subscription.subscriptionPeriod.unit == .year, subscription.subscriptionPeriod.value == 1 else { return nil }
        guard let monthlyProduct = controller.products.first(where: { $0.id == SubscriptionController.monthlyProductID }) else {
            return nil
        }

        let yearlyPrice = NSDecimalNumber(decimal: product.price)
        let monthlyPrice = NSDecimalNumber(decimal: monthlyProduct.price)
        guard monthlyPrice.compare(NSDecimalNumber.zero) == .orderedDescending else { return nil }

        let fullYearPrice = monthlyPrice.multiplying(by: NSDecimalNumber(value: 12))
        guard fullYearPrice.compare(NSDecimalNumber.zero) == .orderedDescending else { return nil }

        let savings = fullYearPrice.subtracting(yearlyPrice)
        guard savings.compare(NSDecimalNumber.zero) == .orderedDescending else { return nil }

        let percentage = savings
            .dividing(by: fullYearPrice)
            .multiplying(by: NSDecimalNumber(value: 100))
            .rounding(accordingToBehavior: nil)

        return percentage.intValue
    }
}

#Preview {
    PaywallView(controller: SubscriptionController())
}
