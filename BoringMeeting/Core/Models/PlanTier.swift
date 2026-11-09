import Foundation
import Observation

enum PlanTier: String, Codable, CaseIterable {
    case free

    var badgeTitle: String {
        switch self {
        case .free:
            return "FREE"
        }
    }

    var marketingDescriptor: String {
        switch self {
        case .free:
            return "your private meeting transcriber"
        }
    }
}

@MainActor
@Observable
final class PlanManager {
    static let shared = PlanManager()

    var currentTier: PlanTier = .free

    private init() {}
}
