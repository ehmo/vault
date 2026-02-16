import ActivityKit
import Foundation

struct TransferActivityAttributes: ActivityAttributes {
    enum TransferType: String, Codable {
        case uploading
        case downloading
    }

    let transferType: TransferType

    struct ContentState: Codable, Hashable {
        let progress: Int
        let total: Int
        let message: String
        let isComplete: Bool
        let isFailed: Bool
        /// Drives pixel grid animation frame. Increments every timer tick (~0.1s)
        /// since TimelineView(.animation) does not re-render in widget extensions.
        var animationStep: Int = 0
    }
}
