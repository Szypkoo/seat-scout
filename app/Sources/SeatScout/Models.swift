import Foundation

enum AppTab: Int, CaseIterable, Identifiable {
    case live = 0
    case segments = 1
    case seats = 2
    case saved = 3
    case developer = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .live: return "Na żywo"
        case .segments: return "Plan miejsc"
        case .seats: return "Fotele"
        case .saved: return "Śledzone"
        case .developer: return "Developer"
        }
    }

    var iconName: String {
        switch self {
        case .live: return "bolt.fill"
        case .segments: return "point.topleft.down.to.point.bottomright.curvepath"
        case .seats: return "chair.lounge.fill"
        case .saved: return "bell.fill"
        case .developer: return "terminal.fill"
        }
    }
}

struct TrainInfo: Identifiable, Equatable {
    let id: String
    let number: String
    let name: String
    let fromStation: String
    let departureTime: String
    let toStation: String
    let arrivalTime: String
    let duration: String
    let basePrice: Double
    let wagonNumber: Int
    let freeSeatsCount: Int
}

struct DiscountOption: Identifiable {
    let id = UUID()
    let name: String
    let discountPercent: Int
    let badgeText: String
}

struct WagonCount: Identifiable, Hashable {
    let wagon: Int
    let free: Int
    let total: Int
    var id: Int { wagon }
}

struct SegmentItem: Identifiable {
    let id = UUID()
    let from: String
    let to: String
    let depTime: String
    let arrTime: String
    let freeSeats: Int
    let occupancyPercent: Int
    var legIndex: Int = -1
    var wagons: [WagonCount] = []
}
