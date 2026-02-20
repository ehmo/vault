import SwiftUI
import StoreKit

struct RatingView: View {
    let onContinue: () -> Void

    @Environment(\.requestReview) private var requestReview

    var body: some View {
        VStack(spacing: 0) {
            Text("Give us a rating")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.top, 20)

            Spacer()

            // Stat section — centered vertically
            VStack(spacing: 0) {
                Text("1M+ vaults\ncreated")
                    .font(.system(size: 38, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                // Overlapping avatars
                HStack(spacing: -10) {
                    ForEach(ReviewData.allReviews.indices, id: \.self) { index in
                        ReviewAvatar(url: ReviewData.allReviews[index].avatarURL, size: 44)
                            .overlay(
                                Circle()
                                    .stroke(Color.vaultBackground, lineWidth: 2.5)
                            )
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 6)

                Text("by people like you")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
            }

            Spacer()

            // Reviews carousel
            VStack(spacing: 14) {
                ReviewCarousel()

                VStack(spacing: 12) {
                    Button(action: {
                        requestReview()
                        onContinue()
                    }) {
                        Text("Rate App")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .vaultSecondaryButtonStyle()
                    .accessibilityIdentifier("rating_rate_app")

                    Button(action: {
                        onContinue()
                    }) {
                        Text("Not Now")
                            .font(.subheadline)
                            .foregroundStyle(.vaultSecondaryText)
                            .padding(.vertical, 8)
                    }
                    .accessibilityIdentifier("rating_not_now")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
        }
        .background(Color.vaultBackground.ignoresSafeArea())
    }
}

// MARK: - Review Avatar

private struct ReviewAvatar: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Circle()
                    .fill(Color.vaultSurface)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - Review Data

private struct ReviewItem: Identifiable {
    let id = UUID()
    let text: String
    let authorName: String
    let avatarURL: URL?
}

private enum ReviewData {
    static let allReviews: [ReviewItem] = [
        ReviewItem(
            text: "I have photos on my phone I'd literally die if anyone saw. Knowing they're behind real encryption and not just a hidden album with a passcode? I can finally breathe.",
            authorName: "jessicam_26",
            avatarURL: URL(string: "https://i.pravatar.cc/96?img=32")
        ),
        ReviewItem(
            text: "My husband and I keep our private photos in a shared vault. No cloud, no accounts, no one at some tech company reviewing our moments. As it should be.",
            authorName: "brooke.h",
            avatarURL: URL(string: "https://i.pravatar.cc/96?img=26")
        ),
        ReviewItem(
            text: "After my divorce I needed somewhere truly private. Not behind a paywall. Not on someone's cloud. Not accessible by lawyers or exes. Actually encrypted. This is it.",
            authorName: "Michelle_R",
            avatarURL: URL(string: "https://i.pravatar.cc/96?img=23")
        ),
        ReviewItem(
            text: "Girls would lose it over photos in my Hidden Album. Vaultaire doesn't even show up as a vault on my phone. No more drama in that department.",
            authorName: "tk_dev",
            avatarURL: URL(string: "https://i.pravatar.cc/96?img=33")
        ),
        ReviewItem(
            text: "I travel through 15+ countries a year. Border agents have asked to see my phone twice. The duress vault saved me both times. Nothing else on the App Store has this.",
            authorName: "marcusj_",
            avatarURL: URL(string: "https://i.pravatar.cc/96?img=12")
        ),
    ]
}

// MARK: - Review Carousel

private struct ReviewCarousel: View {
    @State private var currentIndex = 0

    var body: some View {
        VStack(spacing: 14) {
            TabView(selection: $currentIndex) {
                ForEach(Array(ReviewData.allReviews.enumerated()), id: \.offset) { index, review in
                    ReviewCard(review: review)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 200)
            .vaultGlassBackground(cornerRadius: 12)

            // Dot indicators
            HStack(spacing: 6) {
                ForEach(ReviewData.allReviews.indices, id: \.self) { index in
                    Circle()
                        .fill(index == currentIndex
                              ? Color.vaultSecondaryText
                              : Color.vaultSecondaryText.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
        }
    }
}

// MARK: - Review Card

private struct ReviewCard: View {
    let review: ReviewItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\"\(review.text)\"")
                .font(.subheadline)
                .foregroundStyle(.vaultSecondaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 16)

            HStack(spacing: 10) {
                ReviewAvatar(url: review.avatarURL, size: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text(review.authorName)
                        .font(.caption)
                        .fontWeight(.semibold)

                    HStack(spacing: 1) {
                        ForEach(0..<5, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                    }
                }
            }
        }
        .padding(20)
    }
}

#Preview {
    RatingView(onContinue: {})
}
