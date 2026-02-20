import SwiftUI

struct SubscriptionCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        List {
            Section("Subscription path") {
                Text("Website: Stripe Checkout with Apple Pay")
                Text("iOS/macOS apps: StoreKit subscription flow (next phase)")
                    .foregroundStyle(.secondary)
            }

            Section("Current status") {
                if let capabilities = session.health?.capabilities {
                    Label(capabilities.billing ? "Billing capability available on API" : "Billing capability unavailable on API", systemImage: capabilities.billing ? "checkmark.circle" : "xmark.circle")
                } else {
                    Text("Run health check first.")
                }
            }

            Section("Next implementation") {
                Text("1) Add StoreKit product IDs\n2) Implement purchase/restore\n3) Sync entitlements to Rust API")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Subscription")
    }
}
