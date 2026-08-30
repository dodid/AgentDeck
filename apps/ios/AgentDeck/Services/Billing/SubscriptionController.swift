import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class SubscriptionController {
    static let monthlyProductID = "com.clawchat.plus.monthly"
    static let yearlyProductID = "com.clawchat.plus.yearly"

    private(set) var products: [Product] = []
    private(set) var hasUnlockedAgentAccess = false
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var hasStarted = false
    var errorMessage: String?

    private var transactionUpdatesTask: Task<Void, Never>?

    init() {
        transactionUpdatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard !Task.isCancelled else { break }
                await self?.handle(transactionResult: update)
            }
        }
    }

    func start() async {
        if hasStarted {
            if products.isEmpty && !isLoadingProducts {
                await refreshProducts()
            }
            await refreshEntitlements()
            return
        }

        hasStarted = true
        await refreshProducts()
        await refreshEntitlements()
    }

    func refreshProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let fetched = try await Product.products(for: Self.productIDs)
            products = fetched.sorted(by: Self.productSortOrder)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var isActive = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard Self.productIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            guard transaction.expirationDate.map({ $0 > Date() }) ?? true else { continue }
            guard transaction.isUpgraded == false else { continue }
            isActive = true
            break
        }

        hasUnlockedAgentAccess = isActive
    }

    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = String(localized: "The purchase could not be verified.")
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                errorMessage = nil
                return hasUnlockedAgentAccess
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var recommendedProductID: String {
        Self.yearlyProductID
    }

    func product(id: String) -> Product? {
        products.first(where: { $0.id == id })
    }

    var manageSubscriptionsURL: URL? {
        URL(string: "https://apps.apple.com/account/subscriptions")
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult else { return }
        if Self.productIDs.contains(transaction.productID) {
            await transaction.finish()
            await refreshEntitlements()
        }
    }

    private static let productIDs = [
        monthlyProductID,
        yearlyProductID,
    ]

    private static func productSortOrder(lhs: Product, rhs: Product) -> Bool {
        rank(for: lhs.id) < rank(for: rhs.id)
    }

    private static func rank(for productID: String) -> Int {
        switch productID {
        case yearlyProductID:
            return 0
        case monthlyProductID:
            return 1
        default:
            return 2
        }
    }
}
