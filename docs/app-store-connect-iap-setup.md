# App Store Connect: In-App Purchase Setup

Manual steps required in [App Store Connect](https://appstoreconnect.apple.com) to enable purchases in production.

## 1. Create Subscription Group

1. Go to **Apps > Vaultaire > Monetization > Subscriptions**
2. Click **Create** to add a new subscription group
3. Name: `vaultaire_pro`
4. Reference Name: `Vaultaire Pro`

## 2. Create Subscription Products

Inside the `vaultaire_pro` group, create two subscriptions:

### Monthly Pro

| Field | Value |
|-------|-------|
| Reference Name | Vaultaire Pro Monthly |
| Product ID | `monthly_pro` |
| Duration | 1 Month |
| Price | $1.99 (Tier 2) |
| Subscription Group Level | Level 1 |

### Yearly Pro

| Field | Value |
|-------|-------|
| Reference Name | Vaultaire Pro Yearly |
| Product ID | `yearly_pro` |
| Duration | 1 Year |
| Price | $9.99 (Tier 10) |
| Subscription Group Level | Level 1 |

#### Add Free Trial to Yearly

1. In the `yearly_pro` subscription, go to **Subscription Prices > Introductory Offers**
2. Click **Create Introductory Offer**
3. Type: **Free Trial**
4. Duration: **1 Week**
5. This makes the yearly plan show "7-day free trial" in the paywall

## 3. Create Non-Consumable Product (Lifetime)

1. Go to **Apps > Vaultaire > Monetization > In-App Purchases**
2. Click **Create** (plus button)
3. Type: **Non-Consumable**

| Field | Value |
|-------|-------|
| Reference Name | Vaultaire Pro Lifetime |
| Product ID | `lifetime` |
| Price | $29.99 (Tier 30) |

## 4. Add Localizations

For each product, add at minimum an **English (U.S.)** localization:

| Product | Display Name | Description |
|---------|-------------|-------------|
| monthly_pro | Vaultaire Pro Monthly | Monthly access to all Vaultaire Pro features |
| yearly_pro | Vaultaire Pro Yearly | Yearly access with 7-day free trial |
| lifetime | Vaultaire Pro Lifetime | Lifetime access to all Vaultaire Pro features |

## 5. Review Screenshot

Each product needs a review screenshot before submission. Use a simulator screenshot of the paywall view (any iPhone size works).

## 6. Enable StoreKit Testing in Xcode

For local development/testing:

1. Open Xcode scheme: **Product > Scheme > Edit Scheme**
2. Select **Run** (left sidebar)
3. Go to **Options** tab
4. Set **StoreKit Configuration** to `Products.storekit`

This lets you test purchases in the simulator without needing App Store Connect.

## 7. Sandbox Testing

Before submitting for review:

1. Go to **Users and Access > Sandbox > Testers** in ASC
2. Create a sandbox tester account (use a dedicated email)
3. On a physical device, sign out of your real Apple ID in Settings > App Store
4. Launch the app and attempt a purchase — it will prompt for sandbox credentials
5. Verify: purchase completes, premium unlocks, restore works

## Product ID Reference

These must match exactly between ASC and the code in `SubscriptionManager.swift`:

```
monthly_pro     → Auto-Renewable Subscription (1 month)
yearly_pro      → Auto-Renewable Subscription (1 year, 7-day free trial)
lifetime        → Non-Consumable
```

Subscription Group ID: `vaultaire_pro`
