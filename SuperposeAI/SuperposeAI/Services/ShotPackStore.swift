import StoreKit
import Foundation

@MainActor
@Observable
final class ShotPackStore {
    static let starterProductID = "com.superposelabs.superpose.starter5"
    static let valueProductID = "com.superposelabs.superpose.value20"

    var paidPacksRemaining: Int {
        didSet { UserDefaults.standard.set(paidPacksRemaining, forKey: "paidPacksRemaining") }
    }

    var dailyFreeUsedDate: String? {
        didSet { UserDefaults.standard.set(dailyFreeUsedDate, forKey: "dailyFreeUsedDate") }
    }

    var products: [Product] = []
    var isPurchasing = false
    var purchaseError: String?

    var hasDailyFreePack: Bool {
        dailyFreeUsedDate != Self.todayKey()
    }

    var totalPacksAvailable: Int {
        paidPacksRemaining + (hasDailyFreePack ? 1 : 0)
    }

    init() {
        self.paidPacksRemaining = UserDefaults.standard.integer(forKey: "paidPacksRemaining")
        self.dailyFreeUsedDate = UserDefaults.standard.string(forKey: "dailyFreeUsedDate")
        Task { await loadProducts() }
    }

    func consumeOnePack() -> Bool {
        if hasDailyFreePack {
            dailyFreeUsedDate = Self.todayKey()
            return true
        }
        guard paidPacksRemaining > 0 else { return false }
        paidPacksRemaining -= 1
        return true
    }

    func loadProducts() async {
        do {
            let fetched = try await Product.products(for: [Self.starterProductID, Self.valueProductID])
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            // Products may not be available in offline simulator without .storekit scheme
        }
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                grantPacks(for: product.id)
                await transaction.finish()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func grantPacks(for productID: String) {
        if productID == Self.starterProductID {
            paidPacksRemaining += 5
        } else if productID == Self.valueProductID {
            paidPacksRemaining += 20
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }
}
