import SwiftUI
import StoreKit

struct VaultairePaywallView: View {
    let onDismiss: () -> Void
    var showDismissButton: Bool = true

    @Environment(SubscriptionManager.self) private var subscriptionManager

    @State private var selectedPlan: PlanType = .annual
    @State private var trialEnabled = true
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    // Read products directly from SubscriptionManager (@Observable).
    // No .task needed — view updates reactively when products load from init.
    private var monthlyProduct: Product? { subscriptionManager.product(for: "monthly_pro") }
    private var annualProduct: Product? { subscriptionManager.product(for: "yearly_pro") }
    private var lifetimeProduct: Product? { subscriptionManager.product(for: "lifetime") }

    private var isTrialEligible: Bool {
        guard let annual = annualProduct,
              let sub = annual.subscription,
              let intro = sub.introductoryOffer,
              intro.paymentMode == .freeTrial else { return false }
        return true
    }

    enum PlanType: String, CaseIterable {
        case monthly, annual, lifetime
    }

    var body: some View {
        NavigationStack {
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
            .toolbar {
                if showDismissButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.vaultSecondaryText)
                        }
                        .accessibilityIdentifier("paywall_dismiss")
                    }
                }
            }
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
                type: .annual,
                title: "Annual",
                price: annualProduct?.displayPrice ?? "$9.99",
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

        // Use onTapGesture instead of Button to avoid gesture conflict with
        // ScrollView — Button's internal LongPress→Tap sequence loses taps to
        // the scroll recognizer when the user's finger moves even slightly.
        return HStack {
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
        .background(Color.vaultSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPlan = type
                trialEnabled = type == .annual
            }
        }
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Trial Toggle

    @ViewBuilder
    private var trialToggle: some View {
        if selectedPlan == .annual && isTrialEligible {
            HStack(spacing: 8) {
                Image(systemName: trialEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(trialEnabled ? Color.accentColor : .vaultSecondaryText)
                    .font(.body)
                Text("Enable free 7-day trial")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.vaultText)
                Spacer()
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    trialEnabled.toggle()
                }
            }
            .accessibilityAddTraits(.isButton)
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
        if selectedPlan == .annual && trialEnabled && isTrialEligible {
            return "Try for 7 days"
        }
        switch selectedPlan {
        case .monthly:
            return "Subscribe"
        case .annual:
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
        case .annual: return annualProduct
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
