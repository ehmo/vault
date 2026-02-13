import SwiftUI
import RevenueCat

struct VaultairePaywallView: View {
    let onDismiss: () -> Void

    @Environment(SubscriptionManager.self) private var subscriptionManager

    @State private var selectedPlan: PlanType = .yearly
    @State private var monthlyPackage: Package?
    @State private var yearlyPackage: Package?
    @State private var lifetimePackage: Package?
    @State private var isTrialEligible = false
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    enum PlanType: String, CaseIterable {
        case monthly, yearly, lifetime
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    headerSection
                    benefitsTable
                    planSelector
                    trialCallout
                    ctaButton
                    footerSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color.vaultBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                }
            }
            .task {
                await loadOfferings()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            Text("Unlock Vaultaire")
                .font(.largeTitle.bold())
                .foregroundStyle(.vaultText)

            Text("Full privacy, your terms.")
                .font(.subheadline)
                .foregroundStyle(.vaultSecondaryText)
        }
        .padding(.top, 24)
    }

    // MARK: - Benefits Table

    private var benefitsTable: some View {
        VStack(spacing: 0) {
            // Header row
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
        case "✓":
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
        case "—":
            Text("—")
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
        VStack(spacing: 12) {
            planCard(
                type: .monthly,
                title: "Monthly",
                price: monthlyPackage?.storeProduct.localizedPriceString ?? "$1.99",
                period: "/month",
                badge: nil,
                detail: nil
            )

            planCard(
                type: .yearly,
                title: "Yearly",
                price: yearlyPackage?.storeProduct.localizedPriceString ?? "$9.99",
                period: "/year",
                badge: "SAVE 58%",
                detail: "$0.83/mo"
            )

            planCard(
                type: .lifetime,
                title: "Lifetime",
                price: lifetimePackage?.storeProduct.localizedPriceString ?? "$29.99",
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
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.vaultText)

                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor, in: Capsule())
                        }
                    }

                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.vaultSecondaryText)
                    }
                }

                Spacer()

                Text("\(price)\(period)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.vaultText)
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

    // MARK: - Trial Callout

    @ViewBuilder
    private var trialCallout: some View {
        if selectedPlan == .yearly && isTrialEligible {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.subheadline)
                Text("7-day free trial")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.vaultText)
            }
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
            .disabled(isPurchasing || selectedPackage == nil)
        }
    }

    private var ctaText: String {
        switch selectedPlan {
        case .monthly:
            return "Subscribe"
        case .yearly:
            return isTrialEligible ? "Start Free Trial" : "Subscribe"
        case .lifetime:
            let price = lifetimePackage?.storeProduct.localizedPriceString ?? "$29.99"
            return "Purchase for \(price)"
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 8) {
            Text("No commitment · Cancel anytime")
                .font(.caption)
                .foregroundStyle(.vaultSecondaryText)

            HStack(spacing: 16) {
                Button("Restore Purchases") {
                    Task { await restore() }
                }
                Text("·").foregroundStyle(.vaultSecondaryText)
                Link("Terms", destination: URL(string: "https://vaultaire.app/terms")!)
                Text("·").foregroundStyle(.vaultSecondaryText)
                Link("Privacy", destination: URL(string: "https://vaultaire.app/privacy")!)
            }
            .font(.caption)
            .foregroundStyle(.vaultSecondaryText)
        }
    }

    // MARK: - Data

    private var selectedPackage: Package? {
        switch selectedPlan {
        case .monthly: return monthlyPackage
        case .yearly: return yearlyPackage
        case .lifetime: return lifetimePackage
        }
    }

    private struct BenefitRow {
        let label: String
        let free: String
        let pro: String
    }

    private var benefits: [BenefitRow] {
        [
            BenefitRow(label: "Photos per vault", free: "100", pro: "∞"),
            BenefitRow(label: "Videos per vault", free: "10", pro: "∞"),
            BenefitRow(label: "Vaults", free: "5", pro: "∞"),
            BenefitRow(label: "Duress vault", free: "—", pro: "✓"),
            BenefitRow(label: "Vault sharing", free: "—", pro: "✓"),
            BenefitRow(label: "iCloud backup", free: "—", pro: "✓"),
            BenefitRow(label: "Pattern encryption", free: "✓", pro: "✓"),
            BenefitRow(label: "Plausible deniability", free: "✓", pro: "✓"),
        ]
    }

    // MARK: - Actions

    private func loadOfferings() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            guard let current = offerings.current else { return }

            monthlyPackage = current.package(identifier: "$rc_monthly")
            yearlyPackage = current.package(identifier: "$rc_annual")
            lifetimePackage = current.package(identifier: "$rc_lifetime")

            // Check trial eligibility on yearly product
            if let yearly = yearlyPackage,
               let intro = yearly.storeProduct.introductoryDiscount,
               intro.paymentMode == .freeTrial {
                isTrialEligible = true
            }
        } catch {
            // Packages will show fallback prices from labels
        }
    }

    private func purchase() async {
        guard let package = selectedPackage else { return }
        isPurchasing = true
        errorMessage = nil

        do {
            let result = try await Purchases.shared.purchase(package: package)
            if !result.userCancelled {
                subscriptionManager.updateFromCustomerInfo(result.customerInfo)
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
            let info = try await Purchases.shared.restorePurchases()
            subscriptionManager.updateFromCustomerInfo(info)
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
