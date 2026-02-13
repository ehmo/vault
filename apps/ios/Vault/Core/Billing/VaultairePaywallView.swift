import SwiftUI
import StoreKit

struct VaultairePaywallView: View {
    let onDismiss: () -> Void

    @Environment(SubscriptionManager.self) private var subscriptionManager

    @State private var selectedPlan: PlanType = .monthly
    @State private var monthlyProduct: Product?
    @State private var yearlyProduct: Product?
    @State private var lifetimeProduct: Product?
    @State private var isTrialEligible = false
    @State private var trialEnabled = false
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    enum PlanType: String, CaseIterable {
        case monthly, yearly, lifetime
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                benefitsTable
                planSelector
                trialToggle
                ctaButton
                footerSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color.vaultBackground.ignoresSafeArea())
        .task {
            await loadProducts()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Unlock Vaultaire Pro")
                .font(.title.bold())
                .foregroundStyle(.vaultText)

            Text("Full privacy, your terms.")
                .font(.subheadline)
                .foregroundStyle(.vaultSecondaryText)
        }
    }

    // MARK: - Benefits Table

    private var benefitsTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Feature")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.vaultSecondaryText)
                Spacer()
                Text("FREE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.vaultSecondaryText)
                    .frame(width: 56)
                Text("PRO")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 56)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().opacity(0.3)

            ForEach(benefits, id: \.label) { benefit in
                HStack {
                    Text(benefit.label)
                        .font(.subheadline)
                        .foregroundStyle(.vaultText)
                    Spacer()
                    benefitCell(benefit.free)
                        .frame(width: 56)
                    benefitCell(benefit.pro)
                        .frame(width: 56)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .vaultGlassBackground()
    }

    @ViewBuilder
    private func benefitCell(_ value: String) -> some View {
        switch value {
        case "\u{2713}":
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
        case "\u{2014}":
            Text("\u{2014}")
                .font(.subheadline)
                .foregroundStyle(.vaultSecondaryText)
        default:
            Text(value)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.vaultText)
        }
    }

    // MARK: - Plan Selector

    private var planSelector: some View {
        VStack(spacing: 10) {
            planCard(
                type: .monthly,
                title: "Monthly",
                price: monthlyProduct?.displayPrice ?? "$1.99",
                period: "/month",
                badge: nil,
                detail: nil
            )

            planCard(
                type: .yearly,
                title: "Yearly",
                price: yearlyProduct?.displayPrice ?? "$9.99",
                period: "/year",
                badge: "SAVE 58%",
                detail: "$0.83/mo"
            )

            planCard(
                type: .lifetime,
                title: "Lifetime",
                price: lifetimeProduct?.displayPrice ?? "$29.99",
                period: " once",
                badge: "BEST VALUE",
                detail: "Forever"
            )
        }
    }

    private func planCard(
        type: PlanType,
        title: String,
        price: String,
        period: String,
        badge: String?,
        detail: String?
    ) -> some View {
        let isSelected = selectedPlan == type

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPlan = type
                if type != .yearly {
                    trialEnabled = false
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.vaultText)

                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.vaultSecondaryText)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor, in: Capsule())
                    }

                    Text("\(price)\(period)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.vaultText)
                }
            }
            .padding(16)
            .vaultGlassBackground()
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Trial Toggle

    @ViewBuilder
    private var trialToggle: some View {
        if selectedPlan == .yearly && isTrialEligible {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    trialEnabled.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: trialEnabled ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(trialEnabled ? Color.accentColor : .vaultSecondaryText)
                        .font(.body)
                    Text("Enable free 7-day trial")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.vaultText)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .transition(.opacity)
        }
    }

    // MARK: - CTA Button

    private var ctaButton: some View {
        VStack(spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await purchase() }
            } label: {
                Group {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(ctaText)
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .vaultProminentButtonStyle()
            .disabled(isPurchasing || selectedProduct == nil)
        }
    }

    private var ctaText: String {
        if selectedPlan == .yearly && trialEnabled {
            return "Try for 7 days"
        }
        switch selectedPlan {
        case .monthly:
            return "Subscribe"
        case .yearly:
            return "Subscribe"
        case .lifetime:
            let price = lifetimeProduct?.displayPrice ?? "$29.99"
            return "Purchase for \(price)"
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 8) {
            Text("No commitment \u{00B7} Cancel anytime")
                .font(.caption)
                .foregroundStyle(.vaultSecondaryText)

            HStack(spacing: 16) {
                Button("Restore Purchases") {
                    Task { await restore() }
                }
                Text("\u{00B7}").foregroundStyle(.vaultSecondaryText)
                Link("Terms", destination: URL(string: "https://vaultaire.app/terms")!)
                Text("\u{00B7}").foregroundStyle(.vaultSecondaryText)
                Link("Privacy", destination: URL(string: "https://vaultaire.app/privacy")!)
            }
            .font(.caption)
            .foregroundStyle(.vaultSecondaryText)
        }
    }

    // MARK: - Data

    private var selectedProduct: Product? {
        switch selectedPlan {
        case .monthly: return monthlyProduct
        case .yearly: return yearlyProduct
        case .lifetime: return lifetimeProduct
        }
    }

    private struct BenefitRow {
        let label: String
        let free: String
        let pro: String
    }

    private var benefits: [BenefitRow] {
        [
            BenefitRow(label: "Photos per vault", free: "100", pro: "\u{221E}"),
            BenefitRow(label: "Videos per vault", free: "10", pro: "\u{221E}"),
            BenefitRow(label: "Vaults", free: "5", pro: "\u{221E}"),
            BenefitRow(label: "Duress vault", free: "\u{2014}", pro: "\u{2713}"),
            BenefitRow(label: "Vault sharing", free: "\u{2014}", pro: "\u{2713}"),
            BenefitRow(label: "iCloud backup", free: "\u{2014}", pro: "\u{2713}"),
            BenefitRow(label: "Pattern encryption", free: "\u{2713}", pro: "\u{2713}"),
            BenefitRow(label: "Plausible deniability", free: "\u{2713}", pro: "\u{2713}"),
        ]
    }

    // MARK: - Actions

    private func loadProducts() async {
        await subscriptionManager.loadProducts()

        monthlyProduct = subscriptionManager.product(for: "monthly_pro")
        yearlyProduct = subscriptionManager.product(for: "yearly_pro")
        lifetimeProduct = subscriptionManager.product(for: "lifetime")

        // Check trial eligibility on yearly product
        if let yearly = yearlyProduct,
           let sub = yearly.subscription,
           let intro = sub.introductoryOffer,
           intro.paymentMode == .freeTrial {
            isTrialEligible = true
        }
    }

    private func purchase() async {
        guard let product = selectedProduct else { return }
        isPurchasing = true
        errorMessage = nil

        do {
            let success = try await subscriptionManager.purchase(product)
            if success {
                onDismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isPurchasing = false
    }

    private func restore() async {
        isPurchasing = true
        errorMessage = nil

        do {
            try await subscriptionManager.restorePurchases()
            if subscriptionManager.isPremium {
                onDismiss()
            } else {
                errorMessage = "No active purchases found."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isPurchasing = false
    }
}

#Preview {
    VaultairePaywallView(onDismiss: {})
        .environment(SubscriptionManager.shared)
}
