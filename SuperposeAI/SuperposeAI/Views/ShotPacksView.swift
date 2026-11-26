import SwiftUI
import StoreKit

struct ShotPacksView: View {
    @Environment(ShotPackStore.self) private var shotPackStore
    @Environment(AppState.self) private var appState

    @State private var showLegalSheet = false

    var body: some View {
        NavigationStack {
            List {
                // Balance Section
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Available Shot Packs")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(shotPackStore.totalPacksAvailable)")
                                .font(.system(size: 40, weight: .bold))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Label(
                                shotPackStore.hasDailyFreePack ? "Daily Free Ready" : "Daily Used",
                                systemImage: shotPackStore.hasDailyFreePack ? "gift.fill" : "clock"
                            )
                            .font(.caption.bold())
                            .foregroundStyle(shotPackStore.hasDailyFreePack ? .green : .secondary)

                            Text("1 Pack = 4 AI Pose Ideas")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                // One-Time Packs (No Subscription)
                Section {
                    if shotPackStore.products.isEmpty {
                        fallbackPackRow(title: "Starter Pack (5 Shot Packs)", subtitle: "20 generated pose references • Never expires", price: "$2.99")
                        fallbackPackRow(title: "Value Pack (20 Shot Packs)", subtitle: "80 generated pose references • Best value", price: "$9.99")
                    } else {
                        ForEach(shotPackStore.products, id: \.id) { product in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(product.displayName)
                                        .font(.headline)
                                    Text(product.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(product.displayPrice) {
                                    Task { await shotPackStore.purchase(product) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.cyan)
                                .foregroundStyle(.black)
                                .disabled(shotPackStore.isPurchasing)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("One-Time Shot Packs (No Subscription)")
                } footer: {
                    Text("Shot Packs never expire. Payment is charged to your Apple ID at confirmation of purchase.")
                }

                // Preferences & Legal
                Section("Preferences & Legal") {
                    Picker("Primary Focus", selection: Bindable(appState).preferredUseCase) {
                        ForEach(PoseUseCase.allCases) { useCase in
                            Text(useCase.rawValue).tag(useCase)
                        }
                    }

                    Button {
                        showLegalSheet = true
                    } label: {
                        Label("Privacy Policy & Terms of Use", systemImage: "doc.text")
                    }
                }
            }
            .navigationTitle("Shot Packs")
            .sheet(isPresented: $showLegalSheet) {
                PrivacyAndLegalView()
            }
        }
    }

    private func fallbackPackRow(title: String, subtitle: String, price: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(price)
                .font(.subheadline.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.cyan.opacity(0.2), in: Capsule())
                .foregroundStyle(.cyan)
        }
        .padding(.vertical, 4)
    }
}
