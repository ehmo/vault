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
    }
}
