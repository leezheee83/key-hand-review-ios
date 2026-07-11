import Foundation

enum AmountUnit: String, CaseIterable, Codable, Hashable, Identifiable {
    case bb
    case chips

    var id: String { rawValue }
    var label: String { self == .bb ? "bb" : "筹码" }
}

enum Suit: String, CaseIterable, Codable, Hashable, Identifiable {
    case spade = "♠"
    case heart = "♥"
    case diamond = "♦"
    case club = "♣"

    var id: String { rawValue }
    var isRed: Bool { self == .heart || self == .diamond }
}

struct PlayingCard: Codable, Hashable, Identifiable {
    var rank: String
    var suit: Suit

    var id: String { "\(rank)\(suit.rawValue)" }
    var display: String { id }
}

struct Straddle: Codable, Hashable, Identifiable {
    var id = UUID()
    var position: String
    var amountBB: Double
}

struct ReviewSession: Codable, Identifiable {
    var id = UUID()
    var sb: Double
    var bb: Double
    var currency: String
    var unit: AmountUnit
    var playerCount: Int
    var straddles: [Straddle]
    var createdAt = Date()
    var endedAt: Date?

    var isEnded: Bool { endedAt != nil }
}

struct SessionArchive: Codable, Identifiable {
    var session: ReviewSession
    var hands: [PokerHand]

    var id: UUID { session.id }
}

enum HandStatus: String, Codable, Hashable {
    case draft
    case complete
}

enum StreetKey: String, CaseIterable, Codable, Hashable, Identifiable {
    case preflop
    case flop
    case turn
    case river

    var id: String { rawValue }
    var title: String {
        switch self {
        case .preflop: return "Preflop"
        case .flop: return "Flop"
        case .turn: return "Turn"
        case .river: return "River"
        }
    }

    var shortTitle: String {
        switch self {
        case .preflop: return "翻前"
        case .flop: return "Flop"
        case .turn: return "Turn"
        case .river: return "River"
        }
    }
}

struct HandAction: Codable, Identifiable, Hashable {
    var id = UUID()
    var actor: String
    var action: String
    var amountBB: Double? = nil
    var hero: Bool
}

struct StreetRecord: Codable, Hashable {
    var board: [PlayingCard] = []
    var potBB: Double?
    var confidence: String = "unknown"
    var actions: [HandAction] = []
}

struct ReviewNote: Codable, Hashable {
    var decision = ""
    var basis = ""
    var correction = ""
}

struct PokerHand: Codable, Identifiable, Hashable {
    var id = UUID()
    var createdAt = Date()
    var status: HandStatus = .draft
    var tags: [String] = []
    var heroPosition = "CO"
    var effectiveStackBB: Double = 100
    var heroCards: [PlayingCard] = []
    var playerCount: Int = 8
    var straddles: [Straddle] = []
    var streets: [StreetKey: StreetRecord] = StreetKey.allCases.reduce(into: [:]) { result, key in
        result[key] = StreetRecord()
    }
    var review = ReviewNote()
}

enum AppRoute: Hashable {
    case quick(UUID)
    case route(UUID)
    case detail(UUID)
    case inbox
}
